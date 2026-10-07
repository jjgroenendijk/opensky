// App side of agent control: answers the router from the game view, its
// coordinators, and the streamer (docs/tools/agent-control.md).

import AppKit
import Foundation
import MetalKit
import OpenSkyAgentControl
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld

final class AgentWorldAdapter {
    unowned let game: GameViewController
    /// Set by the host when a mode starts.
    var dataRoot: GameDataRoot?
    var modeName: String?
    /// The diff state behind the game events.
    var tap = AgentEventTapState()
    private var quitScheduled = false

    static let maximumTimeScale = 16.0

    init(game: GameViewController) {
        self.game = game
    }

    var dispatcher: GameInputDispatcher {
        GameInputDispatcher(
            input: game.cameraInput,
            menuMode: game.menuMode,
            openJournal: { [weak game] in game?.journalMenu.open() },
            openInventory: { [weak game] in game?.inventoryMenu.open() },
            onCommand: { [weak game] in game?.runCommand($0) }
        )
    }

    /// True once a cell is in the scene and no door transition is loading.
    var isWorldReady: Bool {
        isWorldLoaded && !game.loadingScreens.isCovering
    }

    /// Cells are in, whether or not a loading screen still covers them. A teleport
    /// that put up the cover waits for this, because it lifts the cover itself.
    var isWorldLoaded: Bool {
        guard game.renderer != nil, let streamer = game.streamer else { return false }
        guard streamer.transitionInFlight == nil else { return false }
        return streamer.interiorScene != nil || !streamer.composition.cells.isEmpty
    }

    func notReady() -> AgentFailure {
        AgentFailure(.notReady, "the world is not loaded yet")
    }
}

extension AgentWorldAdapter: AgentControlWorld {
    var agentStatus: AgentWorldStatus {
        AgentWorldStatus(
            worldReady: isWorldReady,
            dataRoot: dataRoot?.dataURL.path(percentEncoded: false),
            mode: modeName
        )
    }

    var agentTimeline: AgentTimeline {
        let clock = game.simulationClock
        return AgentTimeline(
            frame: clock.frame,
            paused: clock.isFrozen,
            pendingSteps: clock.pendingSteps,
            scale: clock.scale
        )
    }

    func pauseSimulation() {
        game.simulationClock.freeze()
    }

    func resumeSimulation() {
        game.simulationClock.resume()
    }

    func requestSteps(_ count: Int, seconds: Double) {
        game.simulationClock.requestSteps(count, seconds: seconds)
    }

    func setTimeScale(_ scale: Double) throws(AgentFailure) {
        guard scale > 0, scale <= Self.maximumTimeScale else {
            throw AgentFailure(
                .invalidArgument, "scale must be above 0 and at most \(Self.maximumTimeScale)"
            )
        }
        game.simulationClock.setScale(scale)
    }

    func applyInput(_ name: String, phase: AgentInputPhase) throws(AgentFailure) -> Bool {
        guard let action = GameInputAction(rawValue: name) else {
            let known = GameInputAction.allCases.map(\.rawValue).joined(separator: ", ")
            throw AgentFailure(.invalidArgument, "unknown action '\(name)'; known: \(known)")
        }
        let outcome = dispatcher.apply(action, phase == .press ? .press : .release)
        if outcome == .noMenu {
            throw AgentFailure(.invalidArgument, "'\(name)' needs an open menu")
        }
        return action.isHeld
    }

    func look(yawDegrees: Float, pitchDegrees: Float) throws(AgentFailure) {
        guard !game.menuMode.isMenuMode else {
            throw AgentFailure(.invalidArgument, "a menu owns input; close it first")
        }
        let pointsPerDegree = Float.pi / 180 / FreeFlyCamera.lookSensitivity
        game.cameraInput.addLook(
            right: yawDegrees * pointsPerDegree,
            up: pitchDegrees * pointsPerDegree
        )
    }

    func captureScreenshot(_ request: AgentScreenshotRequest) throws(AgentFailure)
        -> AgentHandling
    {
        guard let renderer = game.renderer, let view = game.view as? MTKView else {
            throw notReady()
        }
        if request.offscreen {
            return try .done(.success(captureOffscreen(request, renderer: renderer, view: view)))
        }
        renderer.requestWindowCapture()
        var deadline: Double?
        return .waiting(AgentWait { [weak renderer] now in
            guard let renderer else { return .done(.failure(Self.closed)) }
            let limit = deadline ?? now + Self.windowCaptureSeconds
            deadline = limit
            guard let texture = renderer.takeWindowCapture() else {
                return now < limit ? .wait : .done(.failure(Self.noWindowFrame))
            }
            return .done(Result { () throws(AgentFailure) in
                try Self.write(texture, to: request.path)
                return Self.reply(request, texture: texture, source: "window")
            })
        })
    }

    private static let windowCaptureSeconds = 2.0
    private static let closed = AgentFailure(.notReady, "the game closed")
    private static let noWindowFrame = AgentFailure(
        .failed, "the window presented no frame in 2 s; is it hidden? --offscreen renders one"
    )

    /// A second render at any size. A paused offscreen frame advances no clock, so
    /// a capture does not move the simulation that a deterministic run depends on.
    private func captureOffscreen(
        _ request: AgentScreenshotRequest, renderer: Renderer, view: MTKView
    ) throws(AgentFailure) -> AgentJSON {
        let width = request.width ?? Int(view.drawableSize.width.rounded())
        let height = request.height ?? Int(view.drawableSize.height.rounded())
        guard width > 0, height > 0 else { throw notReady() }
        let saved = (renderer.worldSimPaused, renderer.uiEnabled, renderer.swfEnabled)
        renderer.worldSimPaused = true
        if request.worldOnly {
            renderer.uiEnabled = false
            renderer.swfEnabled = false
        }
        defer {
            (renderer.worldSimPaused, renderer.uiEnabled, renderer.swfEnabled) = saved
        }
        let texture: MTLTexture
        do {
            texture = try renderer.renderOffscreen(width: width, height: height)
        } catch {
            throw AgentFailure(.failed, "screenshot failed: \(error.localizedDescription)")
        }
        try Self.write(texture, to: request.path)
        return Self.reply(request, texture: texture, source: "offscreen")
    }

    private static func write(_ texture: MTLTexture, to path: String) throws(AgentFailure) {
        let url = URL(filePath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FrameScreenshot.write(texture: texture, to: url)
        } catch {
            throw AgentFailure(.failed, "screenshot failed: \(error.localizedDescription)")
        }
    }

    private static func reply(
        _ request: AgentScreenshotRequest, texture: MTLTexture, source: String
    ) -> AgentJSON {
        [
            "path": .string(request.path), "width": .init(texture.width),
            "height": .init(texture.height), "worldOnly": .bool(request.worldOnly),
            "source": .string(source)
        ]
    }

    func quitApplication() {
        guard !quitScheduled else { return }
        quitScheduled = true
        // A short delay lets the reply leave the socket before the app exits.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            NSApplication.shared.terminate(nil)
        }
    }
}
