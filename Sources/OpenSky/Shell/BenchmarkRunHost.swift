// Starts a benchmark tour from the app's launch arguments or the launcher, and
// ends it: the toolbar comes off, then the app quits or the launcher shows the
// result. `openskycli benchmark` launches the app with `--benchmark-request`.

import AppKit
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyWorld

@MainActor
final class BenchmarkRunHost {
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Benchmark"
    )

    /// The tour the next Play window runs.
    private(set) var pending: BenchmarkRequest?
    /// True for a tour from the launch arguments, which also reports the app start.
    private var fromLaunchArguments = false
    /// The tour this host started; a tour an agent starts ends without closing anything.
    private var started: BenchmarkRequest?
    private let playToolbar = BenchmarkToolbarItems()
    /// Called after a launcher run ends, so the launcher can show the result.
    var onLauncherRunFinished: (() -> Void)?
    private weak var tour: BenchmarkWorldAdapter?
    private var watchdogTimer: Timer?
    private var watchdog: BenchmarkWatchdog?
    /// Keeps the Mac and its display awake: a sleeping display stops the frame loop.
    private var awake: (any NSObjectProtocol)?

    /// Reads `--benchmark` or `--benchmark-request`; a malformed request logs and quits.
    func readLaunchArguments(_ arguments: [String] = CommandLine.arguments) -> Bool {
        do {
            guard let request = try BenchmarkRequest.fromAppArguments(arguments)
            else { return false }
            try PlayerSettingsOverrides.set(request.settingOverrides())
            pending = request
            fromLaunchArguments = true
            armWatchdog()
            return true
        } catch {
            Self.logger.error("[ERROR] benchmark request: \(error.description, privacy: .public)")
            NSApplication.shared.terminate(nil)
            return false
        }
    }

    func queueLauncherRun(_ request: BenchmarkRequest) {
        pending = request
        fromLaunchArguments = false
    }

    /// A hidden run's window never comes on the screen.
    var hidesNextWindow: Bool {
        pending?.display == .hidden
    }

    /// A tour sets its own display mode, so the saved full-screen choice waits.
    var ownsNextWindow: Bool {
        pending != nil
    }

    /// The recorder the world load attaches when a tour will run.
    func loadPhasesForNextLoad() -> LoadPhaseRecorder? {
        pending == nil ? nil : LoadPhaseRecorder()
    }

    /// Wires a new game window; it starts the pending tour once its session starts.
    func attach(game: GameViewController, window: NSWindow) {
        game.onSessionStart = { [weak self, weak window] session in
            // Muted before the first frame, so the world's first sounds stay silent too.
            if self?.pending?.muted == true {
                session.audio.outputMuted = true
            }
            guard let window else { return }
            self?.attach(tour: session.benchmarkWorld, window: window)
        }
    }

    private func attach(tour: BenchmarkWorldAdapter, window: NSWindow) {
        self.tour = tour
        playToolbar.benchmark = tour
        tour.onRunningChange = { [weak window, playToolbar] running in
            playToolbar.refresh()
            guard let window else { return }
            window.toolbar = running ? playToolbar.makeToolbar() : nil
        }
        tour.onFinish = { [weak self, weak window] run in
            self?.finished(run, window: window)
        }
        guard let request = pending else { return }
        pending = nil
        tour.reportsAppStart = fromLaunchArguments
        do {
            try tour.start(request)
            started = request
        } catch {
            Self.logger
                .error("[ERROR] benchmark not started: \(error.description, privacy: .public)")
        }
    }

    private func finished(_ run: BenchmarkRun, window: NSWindow?) {
        let folder = run.folder.path(percentEncoded: false)
        if let writeError = run.writeError {
            Self.logger
                .error("[ERROR] benchmark result not written: \(writeError, privacy: .public)")
        } else {
            Self.logger.info("benchmark result: \(folder, privacy: .public)")
        }
        guard let request = started else { return }
        started = nil
        if fromLaunchArguments {
            disarmWatchdog()
            if request.quitWhenDone {
                NSApplication.shared.terminate(nil)
            }
            return
        }
        window?.close()
        onLauncherRunFinished?()
    }

    private func armWatchdog() {
        awake = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "OpenSky benchmark run"
        )
        watchdog = BenchmarkWatchdog(now: ProcessInfo.processInfo.systemUptime)
        watchdogTimer = Timer.scheduledTimer(
            withTimeInterval: BenchmarkWatchdog.checkIntervalSeconds, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkWatchdog() }
        }
    }

    private func checkWatchdog() {
        let frames = tour?.framesDrawn ?? 0
        let now = ProcessInfo.processInfo.systemUptime
        guard let reason = watchdog?.check(frameCount: frames, now: now) else { return }
        abandon(reason)
    }

    private func disarmWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        watchdog = nil
        awake.map(ProcessInfo.processInfo.endActivity)
        awake = nil
    }

    /// The CLI then reports that the app wrote no result.
    private func abandon(_ reason: String) {
        disarmWatchdog()
        Self.logger.error("[ERROR] benchmark ended: \(reason, privacy: .public)")
        NSApplication.shared.terminate(nil)
    }
}
