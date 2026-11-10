// App side of agent control: answers the router from the game view, its
// coordinators, and the streamer (docs/tools/agent-control.md).

public import Foundation
import MetalKit
import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
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
    var streamer: any CellStreamerPort { get }
    var titleMenu: any TitleMenuPort { get }
    var dataRoot: GameDataRoot? { get }
}

public final class AgentWorldAdapter {
    public let hub: AgentHub
    public var game: any AgentWorldHost {
        hub.game
    }

    /// Set by the session scope, because quitting is the app shell's work.
    public var terminateApp: () -> Void = {}
    private var quitScheduled = false

    public static let maximumTimeScale = 16.0
    /// How long a quit waits, so the reply leaves the socket before the app exits.
    private static let replyDrainSeconds = 0.2

    public init(
        game: some AgentWorldHost & AgentRenderHost & AgentActorsHost & AgentMotionHost &
            AgentBehaviourHost & AgentObjectsHost & AgentMenuReadoutHost & AgentScreensHost &
            AgentEventsHost & AgentPlayerReadoutHost & AgentFrameReadoutHost &
            AgentActorReadoutHost &
            AgentItemsHost & AgentViewHost & AgentInputHost & AgentCaptureHost,
        now: @escaping () -> Date
    ) {
        hub = AgentHub(game: game, now: now)
    }

    public var render: AgentRenderAdapter {
        hub.render
    }

    public var actors: AgentActorsAdapter {
        hub.actors
    }

    public var motion: AgentMotionAdapter {
        hub.motion
    }

    public var behaviour: AgentBehaviourAdapter {
        hub.behaviour
    }

    public var objects: AgentObjectsAdapter {
        hub.objects
    }

    public var menuReadout: AgentMenuReadoutAdapter {
        hub.menuReadout
    }

    public var screens: AgentScreensAdapter {
        hub.screens
    }

    public var events: AgentEventsAdapter {
        hub.events
    }

    public var playerReadout: AgentPlayerReadoutAdapter {
        hub.playerReadout
    }

    public var frameReadout: AgentFrameReadoutAdapter {
        hub.frameReadout
    }

    public var actorReadout: AgentActorReadoutAdapter {
        hub.actorReadout
    }

    public var items: AgentItemsAdapter {
        hub.items
    }

    public var view: AgentViewAdapter {
        hub.view
    }

    public var input: AgentInputAdapter {
        hub.input
    }

    public var capture: AgentCaptureAdapter {
        hub.capture
    }

    public var dataRoot: GameDataRoot? {
        hub.dataRoot
    }

    public var isWorldReady: Bool {
        hub.isWorldReady
    }

    public func viewJob(_ target: AgentViewTarget) throws(AgentFailure) -> AgentTeleportJob {
        try hub.viewJob(target)
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
        hub.agentTimeline
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
        Task { @MainActor [terminateApp] in
            await attempt { try await Task.sleep(for: .seconds(Self.replyDrainSeconds)) }
            terminateApp()
        }
    }
}

extension AgentWorldAdapter: AgentWorldPort {}
