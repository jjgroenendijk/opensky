// App lifecycle. The app opens on the launcher, where the user picks the game
// folder and presses Play. The launcher shows the world load, then the game
// window opens. Closing the game window returns to the launcher.

import AppKit
import MetalKit
import OpenSkyAgentControl
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyReference
import OpenSkyWorld

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let gameContext = GameLaunchContext()
    private let worldLoader = WorldLoader()
    private var launcher: LauncherViewController?
    private var launcherWindow: NSWindow?
    private(set) var gameWindow: NSWindow?
    private var settingsController: SettingsWindowController?
    private var agentControl: AgentControlHost?
    private let benchmarkHost = BenchmarkRunHost()
    let referenceSession = ReferenceGameSession()

    /// True while the game window is up.
    private(set) var isPlaying = false
    /// Where the next Play window starts: a launcher start option or a save to continue.
    private var pendingStart = LaunchStart.normal
    private var pendingContinueSlot: String?
    /// Where the next Play window's content goes, such as beside the reference game.
    private var pendingContentRect: CGRect?

    func applicationDidFinishLaunching(_: Notification) {
        // The shell is a committed dark design (Theme.swift): forcing dark
        // appearance keeps every system control on the charcoal palette.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        NSApplication.shared.mainMenu = MainMenu.make(target: self)
        agentControl = AgentControlHost()
        benchmarkHost.onLauncherRunFinished = { [weak self] in
            self?.launcher?.showPage(id: "benchmark")
        }

        if benchmarkHost.readLaunchArguments() {
            begin(atTitleScreen: false, showingLauncher: false)
        } else if LaunchPreferences.skipsLauncher() {
            begin(atTitleScreen: LaunchPreferences.forcedTitleScreen(), showingLauncher: false)
        } else {
            showLauncher()
        }
        NSApplication.shared.activate()
    }

    func applicationWillTerminate(_: Notification) {
        worldLoader.cancel()
        agentControl?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    // MARK: - Launcher

    private func showLauncher() {
        let controller = launcher ?? LauncherViewController(actions: self)
        launcher = controller
        let window = launcherWindow ?? AppWindows.makeLauncher(content: controller)
        launcherWindow = window
        controller.refreshGameFolder()
        window.makeKeyAndOrderFront(nil)
    }

    @objc func returnToLauncher(_: Any?) {
        gameWindow?.close()
    }

    // MARK: - Game window

    private func makeGameWindow(atTitleScreen: Bool) -> NSWindow {
        let game = makeGame()
        game.startsAtTitleScreen = atTitleScreen
        game.launchStart = pendingStart
        game.continueSlot = pendingContinueSlot
        pendingStart = .normal
        pendingContinueSlot = nil
        return AppWindows.makePlay(game: game)
    }

    private func makeGame() -> GameViewController {
        let game = gameContext.makeGameViewController()
        agentControl?.attach(game: game, root: gameContext.gameDataRoot)
        return game
    }

    /// Ends the game. The window is already closing, so this only stops the
    /// draw loop and drops the game graph.
    private func endGame() {
        cancelLoad()
        pauseRendering(gameWindow?.contentViewController as? GameViewController)
        gameWindow?.delegate = nil
        gameWindow = nil
        isPlaying = false
    }

    /// Stops the draw loop of a game view that is leaving its window.
    private func pauseRendering(_ game: GameViewController?) {
        (game?.viewIfLoaded as? MTKView)?.isPaused = true
    }

    // MARK: - Settings

    @objc func openSettings(_: Any?) {
        let controller = settingsController ?? SettingsWindowController()
        settingsController = controller
        controller.onSettingsChanged = { [weak self] in self?.gameFolderDidChange() }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// A settings change applies without a relaunch, to whatever is running.
    /// The launcher shows the load, and the new game view swaps in after it.
    private func reloadRunningGame() {
        guard isPlaying else { return }
        gameContext.resolve()
        showLauncher()
        loadWorld { [weak self] in self?.swapRunningGame() }
    }

    private func swapRunningGame() {
        guard isPlaying else { return }
        launcherWindow?.orderOut(nil)
        let game = makeGame()
        pauseRendering(gameWindow?.contentViewController as? GameViewController)
        gameWindow?.contentViewController = game
        if let gameWindow {
            benchmarkHost.attach(game: game, window: gameWindow)
        }
    }
}

extension AppDelegate: LauncherActions {
    func play(from start: LaunchStart) {
        pendingStart = start
        pendingContinueSlot = nil
        begin(atTitleScreen: pendingStart == .normal)
    }

    func continueGame(slot: String) {
        pendingStart = .normal
        pendingContinueSlot = slot
        begin(atTitleScreen: false)
    }

    func gameFolderDidChange() {
        // A load in the launcher reads the old folder, so it stops.
        if !isPlaying {
            cancelLoad()
        }
        launcher?.refreshGameFolder()
        reloadRunningGame()
    }

    func cancelLoad() {
        worldLoader.cancel()
        launcher?.endLoad()
    }

    func referenceView() -> ReferenceView? {
        let game = gameWindow?.contentViewController as? GameViewController
        return try? game?.session?.agentWorld.referenceView()
    }

    func followReference(_ view: ReferenceView) -> Bool {
        let game = gameWindow?.contentViewController as? GameViewController
        guard let session = game?.session, view.feet.count == 3 else { return false }
        session.menuWorld.followView(AgentViewTarget(
            feet: SIMD3(view.feet[0], view.feet[1], view.feet[2]), yawDegrees: view.yawDegrees,
            pitchDegrees: view.pitchDegrees, worldspace: view.worldspaceEditorID,
            interiorCell: view.interiorFormID, hour: view.gameHour, weather: view.weatherFormID
        ))
        return true
    }

    func placeNextGameWindow(contentRect: CGRect) {
        pendingContentRect = contentRect
    }

    func captureWorld(to url: URL, width: Int, height: Int) throws {
        let game = gameWindow?.contentViewController as? GameViewController
        guard let world = game?.session?.agentWorld else {
            throw ReferenceCaptureError.openSkyFailed("Start the game in OpenSky first.")
        }
        let request = AgentScreenshotRequest(
            path: url.path(percentEncoded: false), width: width, height: height, worldOnly: true
        )
        do {
            _ = try world.captureScreenshot(request)
        } catch {
            throw ReferenceCaptureError.openSkyFailed(error.message)
        }
    }

    func runBenchmark(_ request: BenchmarkRequest) {
        benchmarkHost.queueLauncherRun(request)
        pendingStart = .normal
        pendingContinueSlot = nil
        begin(atTitleScreen: false)
    }

    /// A forced start skips the launcher, so its load shows no readout.
    private func begin(atTitleScreen: Bool, showingLauncher: Bool = true) {
        guard GameFolderStatus().isFound else {
            showLauncher()
            return
        }
        gameContext.resolve()
        gameContext.benchmarkLoadPhases = benchmarkHost.loadPhasesForNextLoad()
        if showingLauncher {
            showLauncher()
        }
        loadWorld { [weak self] in self?.open(atTitleScreen: atTitleScreen) }
    }

    /// The load runs off the main actor, so the launcher stays responsive and
    /// draws each stage as it starts and finishes.
    private func loadWorld(then finish: @escaping () -> Void) {
        launcher?.beginLoad()
        gameContext.load(
            with: worldLoader,
            onUpdate: { [weak self] timeline, elapsed in
                self?.launcher?.showLoad(timeline, elapsed: elapsed)
            },
            completion: { [weak self] in
                self?.launcher?.endLoad()
                finish()
            }
        )
    }

    private func open(atTitleScreen: Bool) {
        let window = makeGameWindow(atTitleScreen: atTitleScreen)
        window.delegate = self
        gameWindow = window
        isPlaying = true
        if let game = window.contentViewController as? GameViewController {
            benchmarkHost.attach(game: game, window: window)
        }
        window.makeKeyAndOrderFront(nil)
        launcherWindow?.orderOut(nil)
        if let rect = pendingContentRect {
            pendingContentRect = nil
            window.setFrame(window.frameRect(forContentRect: rect), display: true)
        } else if Self.savedSettings().bool(.fullScreen), !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    private static func savedSettings() -> PlayerSettingsStore {
        PlayerSettingsStore(persistence: try? PlayerSettingsFile.defaultFile())
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === gameWindow else { return }
        endGame()
        showLauncher()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(returnToLauncher(_:)): isPlaying
        case #selector(sendReferenceView(_:)), #selector(followReferenceGame(_:)),
             #selector(captureReferencePair(_:)):
            isPlaying && ReferenceSettings.prefix() != nil
        default: true
        }
    }
}
