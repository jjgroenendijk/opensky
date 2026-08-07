// `RagdollWorldSeam` conformance (issue #197, roadmap item 15.6): the five
// answers the ragdoll runtime needs from the session around it.
//
// Every one is a plain read off something that already exists — the streamer's
// resident actors, the render scene's animation playbacks, the cell scene's
// collision candidates, the locomotion bridge's graph, the world-state store.
// Nothing here invents an accounting of its own, which is what keeps the
// runtime's behaviour the same under test as it is in the app.
//
// One answer is an honest non-answer and is worth stating rather than papering
// over: `raiseRagdollEvent(_:on:)` can only reach the player's graph, because
// item 14.6 attached a behavior graph to the player and to nobody else. Every
// NPC death therefore takes the runtime's graph-less fallback and hands off
// immediately, which the runtime counts separately so a session can see that it
// happened rather than assume the graph drove it.

import AppKit
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
}
