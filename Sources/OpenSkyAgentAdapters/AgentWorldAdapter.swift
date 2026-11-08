// App side of agent control: answers the router from the game view, its
// coordinators, and the streamer (docs/tools/agent-control.md).

import Foundation
import MetalKit
import OpenSkyActorPresentation
import OpenSkyActors
public import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyDialogue
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyLoading
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyObjectAnimation
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `AgentWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol AgentWorldHost: AnyObject {
    var runtimeState: any RuntimeStatePort { get }
    var actorWorld: any ActorWorldPort { get }
    var loadingScreens: any LoadingScreenPort { get }
    var renderer: (any RendererPort)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var simulationClock: any SteppedWallClockPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var titleMenu: any TitleMenuPort { get }
    var dataRoot: GameDataRoot? { get }
}

public final class AgentWorldAdapter {
    public unowned let game: any AgentWorldHost
    /// Set by the session scope, because quitting is the app shell's work.
    public var terminateApp: () -> Void = {}
    /// The diff state behind the game events.
    public var tap = AgentEventTapState()
    private var quitScheduled = false

    public static let maximumTimeScale = 16.0

    public let renderHost: any AgentRenderHost
    public let actorsHost: any AgentActorsHost
    public let motionHost: any AgentMotionHost
    public let behaviourHost: any AgentBehaviourHost
    public let objectsHost: any AgentObjectsHost
    public let menuReadoutHost: any AgentMenuReadoutHost
    public let screensHost: any AgentScreensHost
    public let eventsHost: any AgentEventsHost
    public let playerReadoutHost: any AgentPlayerReadoutHost
    public let frameReadoutHost: any AgentFrameReadoutHost
    public let actorReadoutHost: any AgentActorReadoutHost
    public let itemsHost: any AgentItemsHost
    public let viewHost: any AgentViewHost
    public let inputHost: any AgentInputHost
    public let captureHost: any AgentCaptureHost

    public var render: AgentRenderAdapter {
        AgentRenderAdapter(owner: self, game: renderHost)
    }

    public var actors: AgentActorsAdapter {
        AgentActorsAdapter(owner: self, game: actorsHost)
    }

    public var motion: AgentMotionAdapter {
        AgentMotionAdapter(owner: self, game: motionHost)
    }

    public var behaviour: AgentBehaviourAdapter {
        AgentBehaviourAdapter(owner: self, game: behaviourHost)
    }

    public var objects: AgentObjectsAdapter {
        AgentObjectsAdapter(owner: self, game: objectsHost)
    }

    public var menuReadout: AgentMenuReadoutAdapter {
        AgentMenuReadoutAdapter(
            owner: self,
            game: menuReadoutHost
        )
    }

    public var screens: AgentScreensAdapter {
        AgentScreensAdapter(owner: self, game: screensHost)
    }

    public var events: AgentEventsAdapter {
        AgentEventsAdapter(owner: self, game: eventsHost)
    }

    public var playerReadout: AgentPlayerReadoutAdapter {
        AgentPlayerReadoutAdapter(
            owner: self,
            game: playerReadoutHost
        )
    }

    public var frameReadout: AgentFrameReadoutAdapter {
        AgentFrameReadoutAdapter(
            owner: self,
            game: frameReadoutHost
        )
    }

    public var actorReadout: AgentActorReadoutAdapter {
        AgentActorReadoutAdapter(
            owner: self,
            game: actorReadoutHost
        )
    }

    public var items: AgentItemsAdapter {
        AgentItemsAdapter(owner: self, game: itemsHost)
    }

    public var view: AgentViewAdapter {
        AgentViewAdapter(owner: self, game: viewHost)
    }

    public var input: AgentInputAdapter {
        AgentInputAdapter(owner: self, game: inputHost)
    }

    public var capture: AgentCaptureAdapter {
        AgentCaptureAdapter(owner: self, game: captureHost)
    }

    public init(game: some AgentWorldHost & AgentRenderHost & AgentActorsHost & AgentMotionHost &
        AgentBehaviourHost & AgentObjectsHost & AgentMenuReadoutHost & AgentScreensHost &
        AgentEventsHost & AgentPlayerReadoutHost & AgentFrameReadoutHost & AgentActorReadoutHost &
        AgentItemsHost & AgentViewHost & AgentInputHost & AgentCaptureHost)
    {
        renderHost = game
        actorsHost = game
        motionHost = game
        behaviourHost = game
        objectsHost = game
        menuReadoutHost = game
        screensHost = game
        eventsHost = game
        playerReadoutHost = game
        frameReadoutHost = game
        actorReadoutHost = game
        itemsHost = game
        viewHost = game
        inputHost = game
        captureHost = game
        self.game = game
    }

    public var dataRoot: GameDataRoot? {
        game.dataRoot
    }

    /// True once a cell is in the scene and no door transition is loading.
    public var isWorldReady: Bool {
        isWorldLoaded && !game.loadingScreens.isCovering
    }

    /// Cells are in, whether or not a loading screen still covers them. A teleport
    /// that put up the cover waits for this, because it lifts the cover itself.
    public var isWorldLoaded: Bool {
        guard
            game.renderer != nil, let streamer = game.streamer,
            streamer.transitionInFlight == nil else { return false }
        return streamer.interiorScene != nil || !streamer.composition.cells.isEmpty
    }

    public func viewJob(_ target: AgentViewTarget) throws(AgentFailure) -> AgentTeleportJob {
        try view.viewJob(target)
    }

    public func notReady() -> AgentFailure {
        AgentFailure(.notReady, "the world is not loaded yet")
    }
}

extension AgentWorldAdapter: AgentControlWorld {
    public func pollEvents(_ emit: (String, [String: AgentJSON]) -> Void) {
        events.pollEvents(emit)
    }

    public func applyInput(_ name: String, phase: AgentInputPhase) throws(AgentFailure) -> Bool {
        try input.applyInput(name, phase: phase)
    }

    public func look(yawDegrees: Float, pitchDegrees: Float) throws(AgentFailure) {
        try input.look(yawDegrees: yawDegrees, pitchDegrees: pitchDegrees)
    }

    public func selectMenuRow(label: String) throws(AgentFailure) -> AgentJSON {
        try input.selectMenuRow(label: label)
    }

    public func pointMenu(x: Float, y: Float, click: Bool) throws(AgentFailure) -> AgentJSON {
        try input.pointMenu(x: x, y: y, click: click)
    }

    public func typeText(_ text: String) throws(AgentFailure) -> AgentJSON {
        try input.typeText(text)
    }

    public func captureScreenshot(_ request: AgentScreenshotRequest) throws(AgentFailure)
        -> AgentHandling
    {
        try capture.captureScreenshot(request)
    }

    public var agentStatus: AgentWorldStatus {
        AgentWorldStatus(
            worldReady: isWorldReady,
            titleMenuOpen: game.titleMenu.isOpen,
            dataRoot: dataRoot?.dataURL.path(percentEncoded: false)
        )
    }

    public var agentTimeline: AgentTimeline {
        let clock = game.simulationClock
        return AgentTimeline(
            frame: clock.frame,
            paused: clock.isFrozen,
            pendingSteps: clock.pendingSteps,
            scale: clock.scale
        )
    }

    public func pauseSimulation() {
        game.simulationClock.freeze()
    }

    public func resumeSimulation() {
        game.simulationClock.resume()
    }

    public func requestSteps(_ count: Int, seconds: Double) {
        game.simulationClock.requestSteps(count, seconds: seconds)
    }

    public func setTimeScale(_ scale: Double) throws(AgentFailure) {
        guard scale > 0, scale <= Self.maximumTimeScale else {
            throw AgentFailure(
                .invalidArgument, "scale must be above 0 and at most \(Self.maximumTimeScale)"
            )
        }
        game.simulationClock.setScale(scale)
    }

    public func quitApplication() {
        guard !quitScheduled else { return }
        quitScheduled = true
        // A short delay lets the reply leave the socket before the app exits.
        Task { @MainActor [terminateApp] in
            try? await Task.sleep(for: .milliseconds(200))
            terminateApp()
        }
    }
}

extension AgentWorldAdapter: AgentWorldPort {}
