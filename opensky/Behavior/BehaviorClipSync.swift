// Clip synchronization (issue #330): keeping two looping clips of different
// lengths in step, and the Bethesda generator that pairs two characters on one
// animation.
//
// Two mechanisms feed the same seam. A `hkbBlenderGenerator` whose
// `m_indexOfSyncMasterChild` names a child publishes that child's playback
// phase onto every other child, which is what stops a walk clip and a run clip
// of different lengths from drifting out of phase as their blend weight moves.
// A `hkbBlendingTransitionEffect` with the sync bit set publishes the outgoing
// state's phase onto the incoming one, so a crossfade between two locomotion
// cycles does not restart the foot pattern.
//
// Both write `BehaviorGraphInstance.pendingClipPhase`, which
// `BehaviorClipEvaluation` reads. The blender's is continuous, applied every
// update so the children stay locked; the transition's is seed-only, applied
// when the incoming clip activates and never again, because a destination
// clip permanently welded to the state it came from would never advance on its
// own.
//
// `m_indexOfSyncMasterChild` is used by 28 blenders in the vanilla player
// graph. It is preferred here over the blender flag bits precisely because it
// is unambiguous: an index into a child array cannot mean anything else, while
// the flag bit map is still unconfirmed (see the flagged assumptions in
// `docs/engine/behavior-runtime.md`).

import Foundation

nonisolated extension BehaviorGraphInstance {
    /// The playback phase of the first clip generator below `target` that has
    /// run, as a fraction of its own clip window, or nil when the subtree holds
    /// none. Depth first in declared order, so the answer is the same on every
    /// run over the same graph.
    func clipPhase(under target: HKXPointerTarget?) -> Float? {
        guard let target else { return nil }
        var visited: Set<HKXPointerTarget> = []
        var stack: [(target: HKXPointerTarget, depth: Int)] = [(target, 0)]
        while let (current, depth) = stack.popLast() {
            guard depth < Self.maximumDepth, visited.insert(current).inserted else {
                continue
            }
            guard let object = object(at: current) else { continue }
            if object is HKBClipGenerator, let state = nodeStates[current], state.hasSeeded {
                return state.phase
            }
            for reference in object.references.reversed() {
                stack.append((reference.target, depth + 1))
            }
        }
        return nil
    }

    /// `BSSynchronizedClipGenerator`: runs the clip it wraps, and takes part in
    /// phase synchronization like any other clip because the wrapped generator
    /// is an ordinary `hkbClipGenerator`.
    ///
    /// What is still owed is the part that needs a second character:
    /// `m_SyncAnimPrefix` names the partner's half of a paired animation and
    /// `m_fGetToMarkTime` says how long this character has to reach the shared
    /// marker. Neither means anything until item 14.5 has two actors to align,
    /// so every evaluation costs one tally entry rather than an invented
    /// alignment.
    func evaluateSynchronizedClip(
        _ generator: BSSynchronizedClipGenerator,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        tally.note(.synchronizedClipMarkerIgnored)
        return evaluateGenerator(
            at: generator.clipGenerator, depth: depth, deltaTime: deltaTime
        )
    }

    /// The phase a sync master imposes on its siblings, applied every update.
    func continuousClipPhase(of target: HKXPointerTarget?) -> (value: Float, seedOnly: Bool)? {
        clipPhase(under: target).map { ($0, false) }
    }
}
