// Clip synchronization. A synced blender publishes its leader's phase to its siblings
// every update, so walk and run clips stay in step. A synced
// `hkbBlendingTransitionEffect` seeds the incoming clip's phase once. Both write
// `BehaviorGraphInstance.pendingClipPhase` (docs/engine/behavior-clips.md).

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    /// The playback phase of the first clip generator below `target` that has
    /// run, as a fraction of its own clip window, or nil when the subtree holds
    /// none. Depth first in declared order, so the answer is the same on every
    /// run over the same graph.
    public func clipPhase(under target: HKXPointerTarget?) -> Float? {
        firstClip(under: target) { clipTarget, _ in
            nodeStates[clipTarget].flatMap { $0.hasSeeded ? $0.phase : nil }
        }
    }

    /// Seconds one loop of the first playable clip below `target` lasts at its
    /// authored speed, or nil when no clip there is loaded.
    func clipCycleDuration(under target: HKXPointerTarget?) -> Float? {
        firstClip(under: target) { _, generator in
            guard
                let clip = clip(
                    named: generator.animationName, bindingIndex: generator.animationBindingIndex
                ),
                clip.duration > 0
            else { return nil }
            let cropped = clip.duration - max(generator.cropStartAmountLocalTime, 0)
                - max(generator.cropEndAmountLocalTime, 0)
            let length = generator.enforcedDuration > 0 ? generator.enforcedDuration : cropped
            let seconds = generator.playbackSpeed > 0 ? length / generator.playbackSpeed : length
            return seconds > 0 && seconds.isFinite ? seconds : nil
        }
    }

    /// The first non-nil answer over the clip generators below `target`.
    private func firstClip<Answer>(
        under target: HKXPointerTarget?,
        _ answer: (HKXPointerTarget, HKBClipGenerator) -> Answer?
    ) -> Answer? {
        guard let target else { return nil }
        var visited: Set<HKXPointerTarget> = []
        var stack: [(target: HKXPointerTarget, depth: Int)] = [(target, 0)]
        while let (current, depth) = stack.popLast() {
            guard
                depth < Self.maximumDepth, visited.insert(current).inserted,
                let node = compiledNode(at: current) else { continue }
            if
                let generator = node.object as? HKBClipGenerator,
                let found = answer(current, generator)
            {
                return found
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
}
