// Clip synchronization. A blender's `m_indexOfSyncMasterChild` publishes the
// master's phase to its siblings every update, so walk and run clips stay in step. A
// synced `hkbBlendingTransitionEffect` seeds the incoming clip's phase once. Both write
// `BehaviorGraphInstance.pendingClipPhase`. The index is used over the unconfirmed
// flag bits (docs/engine/behavior-clips.md).

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    /// The playback phase of the first clip generator below `target` that has
    /// run, as a fraction of its own clip window, or nil when the subtree holds
    /// none. Depth first in declared order, so the answer is the same on every
    /// run over the same graph.
    public func clipPhase(under target: HKXPointerTarget?) -> Float? {
        guard let target else { return nil }
        var visited: Set<HKXPointerTarget> = []
        var stack: [(target: HKXPointerTarget, depth: Int)] = [(target, 0)]
        while let (current, depth) = stack.popLast() {
            guard depth < Self.maximumDepth, visited.insert(current).inserted else {
                continue
            }
            guard let node = compiledNode(at: current) else { continue }
            if node.object is HKBClipGenerator, let state = nodeStates[current], state.hasSeeded {
                return state.phase
            }
            for child in node.children.reversed() {
                stack.append((child, depth + 1))
            }
        }
        return nil
    }

    /// `BSSynchronizedClipGenerator`: runs and syncs its wrapped clip. The paired part
    /// (`m_SyncAnimPrefix`, `m_fGetToMarkTime`) needs a second actor, so each evaluation
    /// adds a tally entry instead of an invented alignment.
    public func evaluateSynchronizedClip(
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
    public func continuousClipPhase(of target: HKXPointerTarget?)
        -> (value: Float, seedOnly: Bool)?
    {
        clipPhase(under: target).map { ($0, false) }
    }
}
