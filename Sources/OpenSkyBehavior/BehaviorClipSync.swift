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

    /// `BSSynchronizedClipGenerator`: runs its wrapped clip on this actor's tracks of a
    /// paired clip (`m_SyncAnimPrefix`, BehaviorPairedClip.swift). The alignment of the
    /// two actors (`m_fGetToMarkTime`) needs the other actor, so it is tallied instead.
    public func evaluateSynchronizedClip(
        _ generator: BSSynchronizedClipGenerator,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        tally.note(.synchronizedClipMarkerIgnored)
        let outer = syncTrackPrefix
        syncTrackPrefix = generator.syncAnimPrefix ?? ""
        defer { syncTrackPrefix = outer }
        return evaluateGenerator(
            at: generator.clipGenerator, depth: depth, deltaTime: deltaTime
        )
    }

    /// This actor's view of `clip` while a synchronized clip runs: its own tracks,
    /// found by bone name. A clip with no track names is used as it is.
    func pairedView(of clip: any BehaviorClip, named name: String?) -> any BehaviorClip {
        guard
            let prefix = syncTrackPrefix,
            !skeleton.boneNames.isEmpty,
            clip.trackNames.contains(where: { $0 != nil })
        else { return clip }
        let key = prefix + "|" + (name ?? "")
        if let cached = pairedClips[key] {
            return cached
        }
        let paired = PairedBehaviorClip(clip, map: PairedTrackMap(
            trackNames: clip.trackNames, prefix: prefix, boneNames: skeleton.boneNames
        ))
        pairedClips[key] = paired
        return paired
    }

    /// The phase a sync master imposes on its siblings, applied every update.
    public func continuousClipPhase(of target: HKXPointerTarget?)
        -> (value: Float, seedOnly: Bool)?
    {
        clipPhase(under: target).map { ($0, false) }
    }
}
