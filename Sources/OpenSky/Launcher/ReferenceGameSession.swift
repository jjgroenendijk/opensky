// The Windows reference game beside a running OpenSky: starts it, moves its window into
// place, writes OpenSky's view for it, and captures both. The Reference Game page and the
// Game menu share one session, because the launcher hides while the game window is open.

import AppKit
import OpenSkyGameData
import OpenSkyPreview
import OpenSkyReference

@MainActor
final class ReferenceGameSession {
    /// The reference window's frame from the last start, so a capture uses its size.
    private(set) var frame: ReferenceWindowFrame?
    private var start: Task<Void, Never>?
    /// Each status line, such as when Steam is up or a capture ended.
    var onStatus: (ReferenceNotice) -> Void = { _ in }

    /// Seconds a start waits for the game window; Steam and the intro take a while.
    private static let windowWaitSteps = 240
    /// Checks in a row that find the window in place before the move counts as done.
    private static let settledChecks = 5
    private static let noScreenRecordingMessage =
        "Allow OpenSky in Privacy & Security > Screen Recording, then capture again."
    private static let notMovedMessage =
        "Could not move the Windows game. Allow OpenSky in Privacy & Security > Accessibility."

    private var captureFrame: ReferenceWindowFrame {
        let size = ReferencePageActions.defaultWindowSize
        return frame ?? ReferenceWindowFrame(x: 0, y: 0, width: size.0, height: size.1)
    }

    /// Starts Steam and the game without blocking; false when the prefix is not ready.
    func startGame(at frame: ReferenceWindowFrame, lowGraphics: Bool) -> Bool {
        let prefix: ReferencePrefix
        do {
            prefix = try ReferenceLauncher.readyPrefix()
        } catch {
            onStatus(ReferenceNotice(error.localizedDescription, isProblem: true))
            return false
        }
        self.frame = frame
        let options = ReferenceLaunchOptions(
            frame: frame, steamWait: ReferencePageActions.steamWait,
            preset: lowGraphics ? .low : nil
        )
        let waits = !ReferenceLauncher.isSteamRunning()
        onStatus(ReferenceNotice(
            ReferencePageActions.startingMessage(waitsForSteam: waits), isProblem: false
        ))
        start?.cancel()
        start = Task { [weak self] in
            let notice: ReferenceNotice
            do {
                let logs = try ReferencePageActions.runFolder("Wine")
                try await ReferenceLauncher.launch(prefix: prefix, options: options, logs: logs)
                try await self?.moveWindow(to: frame)
                notice = ReferenceNotice(ReferencePageActions.startedMessage, isProblem: false)
            } catch {
                notice = ReferenceNotice(error.localizedDescription, isProblem: true)
            }
            guard !Task.isCancelled else { return }
            self?.onStatus(notice)
        }
        return true
    }

    /// Wine ignores the window place in `SkyrimPrefs.ini`, and places the window again while
    /// the game sets up its display, so the move repeats until the window stays.
    private func moveWindow(to frame: ReferenceWindowFrame) async throws {
        var seen = false
        var stayed = 0
        for _ in 0 ..< Self.windowWaitSteps where stayed < Self.settledChecks {
            try await Task.sleep(for: .seconds(1))
            let window = ReferenceWindowCapture.window(expected: frame).flatMap { found in
                Int(found.width) == frame.width && Int(found.height) == frame.height
                    ? found : nil
            }
            guard let window else { continue }
            seen = true
            if window.isPlaced(at: frame) {
                stayed += 1
            } else if ReferenceWindowMover.move(pid: window.ownerPID, to: frame) {
                stayed = 0
            } else {
                onStatus(ReferenceNotice(Self.notMovedMessage, isProblem: true))
                return
            }
        }
        if !seen {
            throw ReferenceMoveError.noWindow
        }
    }

    func exportView(_ view: ReferenceView?) -> ReferenceNotice {
        ReferencePageActions.exportView(view, prefix: ReferenceSettings.prefix())
    }

    /// Writes the batch file and both captures into one run folder.
    func capture(
        _ view: ReferenceView?, captureWorld: (URL, Int, Int) throws -> Void
    ) -> ReferenceNotice {
        guard let view else {
            return ReferenceNotice("Start the game in OpenSky first.", isProblem: true)
        }
        // Capturing another app's window needs Screen Recording; the request shows the prompt.
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            return ReferenceNotice(Self.noScreenRecordingMessage, isProblem: true)
        }
        let frame = captureFrame
        do {
            let folder = try ReferencePageActions.runFolder("Captures")
            let run = ReferenceComparisonRun(directory: folder)
            let toggles = ReferenceBatchToggles(hideMenus: true, freezeWorld: false)
            try ReferenceConsoleBatch.write(view, toggles: toggles, to: [run.batchFile])
            let report = try ReferenceComparisonCapture.capture(
                into: run, view: view, frame: frame
            ) { try captureWorld($0, frame.width, frame.height) }
            return ReferenceNotice(report.summary, isProblem: false)
        } catch {
            return ReferenceNotice(error.localizedDescription, isProblem: true)
        }
    }
}
