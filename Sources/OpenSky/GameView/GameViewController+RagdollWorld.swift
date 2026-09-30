// `RagdollWorldSeam` conformance: plain reads off the streamer, the render
// scene, the cell scene, the locomotion bridge, and the world-state store.
// `raiseRagdollEvent(_:on:)` reaches only the player's graph, so every NPC death
// takes the graph-less fallback, which the runtime counts separately.

import AppKit
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension GameViewController: RagdollWorldSeam {
    func ragdollActor(for key: ReferenceKey) -> RagdollActor? {
        guard
            let renderer,
            let streamer,
            let entry = streamer.referenceEntry(key: key),
            let actor = entry.placedActor,
            let playback = actorPlayback(for: key),
            let definition = ragdollDefinition(for: playback.clip, scale: actor.scale),
            let animated = playback.clip.orderedWorldTransforms(at: renderer.animationTime)
        else { return nil }
        return RagdollActor(
            key: key,
            cell: streamer.cellLocation(of: key) ?? .interior(actor.formID),
            reference: actor.formID,
            definition: definition,
            animatedBoneMatrices: animated,
            actorToWorld: MatrixMath.placement(
                position: actor.placement.position,
                rotation: actor.placement.rotation,
                scale: actor.scale
            ),
            velocity: .zero
        )
    }

    @discardableResult
    func raiseRagdollEvent(_ name: String, on key: ReferenceKey) -> Bool {
        guard let renderer, key == .player else { return false }
        renderer.locomotion.raise(name)
        // `raisedEvents` holds the names the graph declared a home for and
        // `missingEvents` the ones it did not, so membership after the raise is
        // the graph's own answer rather than an assumption about it.
        return renderer.locomotion.status.raisedEvents.contains(name)
    }

    /// The world a falling corpse collides with: the same static broadphase the
    /// player capsule and the clutter bodies query, at the same gravity.
    var ragdollStepWorld: DynamicStepWorld {
        guard let streamer else { return DynamicStepWorld() }
        return DynamicStepWorld(
            staticCandidates: { [weak streamer] bounds in
                streamer?.collisionCandidates(overlapping: bounds) ?? []
            }
        )
    }

    func writeDeathState(
        _ state: ActorDeathState,
        for key: ReferenceKey,
        in cell: CellSceneLocation
    ) {
        worldState.set(state, for: key, in: cell)
    }

    func deathState(of key: ReferenceKey) -> ActorDeathState? {
        worldState.component(ActorDeathState.self, for: key)
    }

    /// The script half of a death. A session with no VM — a
    /// synthetic scene, an install whose archives carry no `scripts\` entries —
    /// queues nothing and reports zero, which is the honest count rather than a
    /// silent no-op.
    @discardableResult
    func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        papyrus?.queueActorDeath(actor: key, killer: killer) ?? 0
    }
}
