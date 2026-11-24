// Publishes the collision bodies of the living actors near the camera, which the actor
// camera fade sweeps against (docs/engine/actor-camera-fade.md#which-actor-fades).

import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRenderCore
public import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// What `ActorCameraBodiesAdapter` reads from the session.
@MainActor
public protocol ActorCameraBodiesHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var mountWorld: any MountWorldPort { get }
    var ragdoll: any RagdollPort { get }
    var streamer: any CellStreamerPort { get }
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]?
}

public final class ActorCameraBodiesAdapter {
    /// Actors farther than this beyond the sweep cannot touch it.
    static let reach: Float = 300

    public let game: any ActorCameraBodiesHost

    /// Without a stage, as in a test, it registers nothing.
    public init(game: any ActorCameraBodiesHost, stage: SessionStage?) {
        self.game = game
        stage?.gameSession.frameSteps.register(.actorCameraBodies) { [weak self] _ in
            self?.publish()
        }
    }

    /// Each living actor but the player and the ridden mount, with its ragdoll bones where
    /// its animation holds them, or its movement capsule when it has no ragdoll.
    func publish() {
        guard let session = game.gameSession else { return }
        guard session.movementMode.isPlayerControlled else {
            session.actorCameraBodies = []
            return
        }
        let feet = session.walkController.feetPosition
        let eye = session.freeFlyCamera.position
        let range = simd_distance(feet, eye) + Self.reach
        let mount = game.mountWorld.riddenMount
        session.actorCameraBodies = game.actorWorld.combatActors().compactMap { actor in
            guard
                actor.key != .player, actor.key != mount, !actor.isDead,
                simd_distance(actor.feet, feet) < range
            else { return nil }
            return candidate(for: actor)
        }
        .sorted { $0.formID < $1.formID }
    }

    private func candidate(for actor: CombatActorObservation) -> ActorCameraFade.Candidate? {
        let streamer = game.streamer
        guard
            let entry = streamer.referenceEntry(key: actor.key),
            let placed = entry.placedActor
        else { return nil }
        let formID = entry.formID.rawValue
        if
            let ragdoll = game.ragdoll.ragdollDefinition(of: actor.key),
            let pose = game.animatedPose(for: actor.key)
        {
            let frame = streamer.drawnFrame(
                of: actor.key,
                placed: placed.placement,
                scale: placed.scale
            )
            let bodies = ragdoll.worldCapsules(
                boneToActor: pose, actorToWorld: frame.actorToWorld, scale: frame.scale
            ).map { ActorCameraFade.Body(start: $0.start, end: $0.end, radius: $0.radius) }
            if !bodies.isEmpty {
                return ActorCameraFade.Candidate(formID: formID, bodies: bodies)
            }
        }
        let radius = actor.capsule.radius * actor.scale
        let height = actor.capsule.height * actor.scale
        let capsule = ActorCameraFade.Body(
            start: actor.feet + SIMD3(0, 0, radius),
            end: actor.feet + SIMD3(0, 0, max(height - radius, radius)),
            radius: radius, boundRadius: actor.capsule.centreHeight * actor.scale
        )
        return ActorCameraFade.Candidate(formID: formID, bodies: [capsule])
    }
}
