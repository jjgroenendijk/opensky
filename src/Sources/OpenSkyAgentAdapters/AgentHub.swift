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
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Every host an `AgentWorldAdapter` part reads, all one object.
public typealias AgentWorldHosts =
    AgentActorReadoutHost & AgentActorsHost & AgentBehaviourHost & AgentCaptureHost &
    AgentEventsHost & AgentFrameReadoutHost & AgentInputHost & AgentItemsHost &
    AgentMenuReadoutHost &
    AgentMotionHost & AgentObjectsHost & AgentPlayerReadoutHost & AgentRenderHost &
    AgentScreensHost & AgentViewHost & AgentWorldHost

/// What the parts of `AgentWorldAdapter` share: the hosts, the event tap state, and the
/// reads every part uses. A value, so a part holds no reference back to its owner.
public struct AgentHub {
    public let game: any AgentWorldHost
    let state = AgentPartState()
    public let now: () -> Date

    /// The diff state behind the game events.
    public var tap: AgentEventTapState {
        get { state.tap }
        nonmutating set { state.tap = newValue }
    }

    let hosts: any AgentWorldHosts

    public init(
        game: some AgentWorldHosts,
        now: @escaping () -> Date
    ) {
        self.now = now
        hosts = game
        self.game = game
    }

    var dataRoot: GameDataRoot? {
        game.dataRoot
    }

    /// True once a cell is in the scene and no door transition is loading.
    var isWorldReady: Bool {
        isWorldLoaded && !game.loadingScreens.isCovering
    }

    /// Cells are in, whether or not a loading screen still covers them. A teleport
    /// that put up the cover waits for this, because it lifts the cover itself.
    var isWorldLoaded: Bool {
        let streamer = game.streamer
        guard
            game.renderer != nil,
            streamer.transitionInFlight == nil else { return false }
        return streamer.interiorScene != nil || !streamer.composition.cells.isEmpty
    }

    public func notReady() -> AgentFailure {
        AgentFailure(.notReady, "the world is not loaded yet")
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
}

/// The diff state the event tap keeps between polls.
final class AgentPartState {
    var tap = AgentEventTapState()

    init() {}
}
