// App side of `RagdollCoordinator`: steps it from the renderer's frame hooks and
// answers `RagdollSessionWorld` from the streamer, the render scene, and the
// other session systems. The rules live in the coordinator
// (docs/engine/coordinators.md).

import OpenSkyActors
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Answers `RagdollSessionWorld` from the session systems `game` owns.
final class RagdollWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// Chained onto `onWorldUpdate`, so the ragdolls see the same simulated
    /// delta as the other systems, and a menu-paused frame stops a falling
    /// corpse. The pose reaches the scene on the drawn frame, so a paused
    /// corpse stays where it was.
    func wireRagdoll(renderer: Renderer) {
        let ragdoll = game.ragdoll
        ragdoll.wire(collisionModels: game.audioFileSystem.map(NIFCollisionLibrary.init))
        let advanceWorld = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak ragdoll, weak renderer] delta in
            advanceWorld?(delta)
            guard let ragdoll, let renderer else { return }
            let locomotion = renderer.locomotion
            ragdoll.advance(
                events: locomotion.graphEvents.drain(locomotion.ragdollEventConsumer),
                blendDuration: locomotion.ragdollBlendDuration,
                delta: delta
            )
        }
        renderer.onFrame.add { [weak ragdoll] _ in
            ragdoll?.publishPoses()
        }
    }
}

extension RagdollWorldAdapter: RagdollSessionWorld {
    var ragdollResidents: [RagdollResident] {
        guard let streamer = game.streamer else { return [] }
        return streamer.residentActorEntries().compactMap { entry in
            entry.placedActor.map {
                RagdollResident(key: entry.key, position: $0.placement.position)
            }
        }
    }

    func hasZeroHealth(_ key: ReferenceKey) -> Bool {
        guard
            let streamer = game.streamer,
            let values = game.actorValues.runtime,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else { return false }
        return values.hasZeroHealth(ActorValueHolder(
            key: key, subject: .actor(base: actor.base), cell: streamer.cellLocation(of: key)
        ))
    }

    func reportMurder(of key: ReferenceKey) {
        game.crime.reportMurder(of: key)
    }

    func ragdollPose(of key: ReferenceKey) -> RagdollActorPose? {
        guard
            let renderer = game.renderer,
            let streamer = game.streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor,
            let playback = game.actorPlayback(for: key),
            let animated = playback.clip.orderedWorldTransforms(at: renderer.animationTime)
        else { return nil }
        return RagdollActorPose(
            reference: actor.formID,
            cell: streamer.cellLocation(of: key) ?? .interior(actor.formID),
            scale: actor.scale,
            actorToWorld: MatrixMath.placement(
                position: actor.placement.position,
                rotation: actor.placement.rotation,
                scale: actor.scale
            ),
            skeletonMeshPath: playback.clip.skeletonMeshPath,
            skeleton: playback.clip.skeleton,
            animatedBoneMatrices: animated
        )
    }

    func animatedPose(of key: ReferenceKey) -> [String: float4x4]? {
        game.animatedPose(for: key)
    }

    /// Membership in `raisedEvents` after the raise is the graph's own answer.
    func raisePlayerGraphEvent(_ name: String) -> Bool {
        guard let renderer = game.renderer else { return false }
        renderer.locomotion.raise(name)
        return renderer.locomotion.status.raisedEvents.contains(name)
    }

    /// The same static broadphase the player capsule queries.
    var ragdollStepWorld: DynamicStepWorld {
        guard let streamer = game.streamer else { return DynamicStepWorld() }
        return DynamicStepWorld(
            staticCandidates: { [weak streamer] bounds in
                streamer?.collisionCandidates(overlapping: bounds) ?? []
            }
        )
    }

    func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        game.papyrus?.queueActorDeath(actor: key, killer: killer) ?? 0
    }

    var selectedRagdollActor: ReferenceKey? {
        guard let streamer = game.streamer else { return nil }
        if
            let target = streamer.interactionTarget,
            let entry = streamer.referenceEntry(formID: target.interaction.reference),
            entry.placedActor != nil
        {
            return entry.key
        }
        return playerFeetPosition.flatMap { streamer.nearestActorEntry(to: $0)?.key }
    }

    var playerFeetPosition: SIMD3<Float>? {
        game.renderer?.walkController.feetPosition
    }

    /// An ACHR's holder re-derives its baseline from the NPC_'s CNTO list, as
    /// a chest's does, so the corpse needs no new menu.
    func searchCorpse(_ key: ReferenceKey) -> Bool {
        guard
            game.inventory.runtime != nil,
            let streamer = game.streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else { return false }
        game.containerMenu.target(
            InventoryHolder(
                key: key, owner: .actor(base: actor.base), cell: streamer.cellLocation(of: key)
            ),
            name: "Corpse \(key.description)",
            reference: actor.formID
        )
        return true
    }

    var publishedRagdollPoses: [UInt32: [String: float4x4]] {
        get { game.renderer?.scene.ragdollPoses ?? [:] }
        set { game.renderer?.scene.ragdollPoses = newValue }
    }
}
