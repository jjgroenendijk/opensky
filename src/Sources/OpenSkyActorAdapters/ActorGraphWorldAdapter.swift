// App side of the per-actor behaviour graphs: hands the coordinator the loaded actors
// and their race graphs, steps it in the world update, and sends each fired event to
// sounds, footsteps, and Papyrus. The rules live in `ActorGraphCoordinator`
// (docs/engine/actor-graphs.md).

public import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `ActorGraphWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol ActorGraphWorldHost: AnyObject {
    var actorGraphs: any ActorGraphPort { get }
    var actorWorld: any ActorWorldPort { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var dragonFlight: any DragonFlightPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idleWorld: any IdleWorldPort { get }
    var objectAnimationWorld: any ObjectAnimationWorldPort { get }
    var playerSettingsStore: PlayerSettingsStore { get }
    var streamer: (any CellStreamerPort)? { get }
    var vehicleWorld: any VehicleWorldPort { get }
}

public final class ActorGraphWorldAdapter {
    public let game: any ActorGraphWorldHost
    public var graphs: any ActorGraphPort {
        game.actorGraphs
    }

    public let state = ActorGraphPartState()

    /// `path` is nil when the race names no graph.
    public struct GraphBase {
        let path: String?
        let weight: Float
    }

    static let settings: Set<PlayerSettingID> = [
        .actorGraphs, .actorGraphFullRateDistance, .actorGraphDistance
    ]

    public let graphEventsHost: any ActorGraphGraphEventsHost

    public var graphEvents: ActorGraphGraphEventsAdapter {
        ActorGraphGraphEventsAdapter(
            game: graphEventsHost,
            state: state
        )
    }

    public init(game: some ActorGraphWorldHost & ActorGraphGraphEventsHost) {
        graphEventsHost = game
        self.game = game
    }

    /// One NPC mover's drive, as its graph's locomotion inputs.
    public func drive(_ update: NPCLocomotionDriveUpdate) {
        let moving = update.intent != .still
        state.gaits[update.actor] = update.gait
        state.groundMaterials[update.actor] = update.groundMaterial
        if moving {
            state.movers.insert(update.actor)
        } else {
            state.movers.remove(update.actor)
        }
        graphs.setMotion(
            ActorGraphMotion(
                isMoving: moving,
                isSprinting: moving && update.gait == .sprint,
                isSneaking: update.gait == .sneak
            ),
            for: update.actor
        )
    }

    /// Every running graph's variables, the player's included.
    public func graphVariableResolution() -> GraphVariableResolution {
        graphs.variableResolution(player: game.gameSession?.locomotion.graph?.variables)
    }
}

extension ActorGraphWorldAdapter: ActorGraphWorld {
    public func animationWaitFinished(token: UInt64, fired: Bool) {
        game.objectAnimationWorld.answerWait(token: token, fired: fired)
    }

    public func actorGraphCandidates() -> [ActorGraphCandidate] {
        guard let streamer = game.streamer else { return [] }
        // A rider plays the rider clips of its mount's gait instead.
        let links = game.vehicleWorld.vehicles.core.links
        return game.actorWorld.combatActors().compactMap { actor in
            guard
                !actor.isDead, links[actor.key] == nil,
                let placed = streamer.residentActorEntry(key: actor.key)?.placedActor,
                let graphBase = graphEvents.graphBase(of: actor.key, base: placed.base),
                let path = graphBase.path
            else { return nil }
            return ActorGraphCandidate(
                key: actor.key, projectPath: path, feet: actor.feet, rotationZ: actor.facing,
                weight: graphBase.weight, scale: placed.scale
            )
        }
    }

    public var actorGraphViewer: SIMD3<Float>? {
        game.gameSession?.freeFlyCamera.position
    }

    /// A seat, a furniture clip, a paired clip, or a flight already places the actor.
    public func applyRootMotion(_ step: ActorRootMotionStep, to actor: ReferenceKey) {
        let idles = game.idleWorld.idles
        guard
            idles.furnitureResolution.uses[actor] == nil, idles.rootMotion(of: actor) == nil,
            !idles.pairs.contains(where: { $0.lead == actor || $0.partner == actor }),
            game.dragonFlight.phase(of: actor) == .grounded
        else { return }
        game.streamer?.moveStandingActor(
            actor, by: step.displacement, turning: step.headingTurn
        )
    }
}

extension ActorGraphWorldAdapter: ActorGraphWorldPort {}
