// App side of the idle runtime and the head assembly switch. It answers their
// ports from the session systems and runs the idle pass in the frame loop.
// See docs/engine/coordinators.md.

public import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyBehavior
public import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `IdleWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol IdleWorldHost: AnyObject {
    var aiWorld: any AIWorldPort { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var idles: any IdlePort { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var animationClips: ActorClipLoader? { get }
    var vehicleWorld: any VehicleWorldPort { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

public final class IdleWorldAdapter {
    public let game: any IdleWorldHost
    public var idles: any IdlePort {
        game.idles
    }

    public let placementHost: any IdlePlacementHost

    public var placement: IdlePlacementAdapter {
        IdlePlacementAdapter(game: placementHost)
    }

    public init(game: some IdleWorldHost & IdlePlacementHost) {
        placementHost = game
        self.game = game
    }

    /// The clip loader is built first.
    public func sessionData() -> IdleSessionData? {
        guard
            let store = game.worldData?.idleStore,
            let files = game.audioFileSystem,
            let clips = game.animationClips
        else { return nil }
        return IdleSessionData(
            store: store, files: files, clips: clips, conditionFunctions: .standard
        )
    }
}

extension IdleWorldAdapter: IdleWorld {
    public func idleAnimationEvent(_ name: String, on actor: ReferenceKey) {
        game.vehicleWorld.handleIdleAnimationEvent(name, from: actor)
    }

    public func idleConditionContext() -> ConditionContext {
        guard let clock = game.gameSession?.gameClock else { return ConditionContext() }
        var context = game.aiWorld.packageConditionContext(clock: clock)
        // Idle trees test keywords, such as the chopping block's `isExecutioner`.
        context.data = game.runtimeStateWorld.conditionData()
        return context
    }

    public var idleStateSequence: UInt64 {
        game.worldState.nextJournalSequence
    }

    public func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult {
        game.aiWorld.moveActor(actor, to: point)
    }
}

extension IdleWorldAdapter: IdleWorldPort {}
