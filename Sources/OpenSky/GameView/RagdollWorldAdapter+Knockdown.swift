// What a knockdown does to the rest of the session: the movement runtime holds the actor
// while it lies, the graph enters its ragdoll and get-up states, and the actor stands
// where its body lies (docs/engine/ragdoll.md#knockdown).

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyWorld
import simd

extension RagdollWorldAdapter {
    /// The actor stops where it falls, so no package walks its capsule away. The player's
    /// controls lock, and a first-person view steps out to show the fall.
    func enterKnockdown(_ key: ReferenceKey) {
        guard key != .player else {
            if game.gameSession?.movementMode == .walk {
                game.gameSession?.setMovementMode(.thirdPerson)
            }
            game.gameSession?.locomotion.raise(RagdollGraphNames.ragdollInstant)
            return
        }
        _ = game.streamer?.takeRiddenActor(key)
        _ = game.actorGraphWorld.graphs.raise(RagdollGraphNames.ragdollInstant, on: key)
    }

    /// The graph's `iGetUpType` already reads 2 in water, so only the event is raised.
    func getUp(_ key: ReferenceKey, feet: SIMD3<Float>, yaw: Float?) {
        guard key != .player else {
            game.gameSession?.placePlayerFeet(at: feet)
            game.gameSession?.locomotion.raise(RagdollGraphNames.getUpStart)
            return
        }
        if let streamer = game.streamer {
            let facing = yaw ?? streamer.riddenHold(of: key)?.yaw ?? 0
            streamer.steerRiddenActor(key, to: feet, yaw: facing)
        }
        _ = game.actorGraphWorld.graphs.raise(RagdollGraphNames.getUpStart, on: key)
    }

    func endKnockdown(_ key: ReferenceKey) {
        guard key != .player else { return }
        _ = game.streamer?.releaseRiddenActor(key)
    }

    func getUpDuration(of key: ReferenceKey) -> Float? {
        let graph = key == .player
            ? game.gameSession?.locomotion.graph
            : game.actorGraphWorld.graphs.instance(of: key)
        guard let duration = graph?.physicsRequests.getUp?.duration, duration > 0 else {
            return nil
        }
        return duration
    }
}
