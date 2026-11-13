// The children of one `hkbBlenderGenerator` update: their weights, authored or
// parametric, and the shared cycle of a synced blender, which plays every child at the
// speed that ends their loops together (docs/engine/behavior-clips.md#clip-synchronization).

import Foundation
import OpenSkyFormatsAnimation

/// One decoded `hkbBlenderGeneratorChild` with the values bound onto it.
nonisolated struct BehaviorBlenderEntry {
    let child: HKBBlenderGeneratorChild
    let bound: [String: BehaviorVariableValue]
    /// A bone weight array the child binds from a character property.
    var characterWeights: [Float]?
}

nonisolated extension BehaviorGraphInstance.Blenders {
    /// `hkbBlenderGenerator`: mixes child poses by `m_weight` and root travel by
    /// `m_worldFromModelWeight`. A bone whose weights sum to at most
    /// `m_referencePoseWeightThreshold` takes the reference pose for the rest.
    func evaluateBlend(
        _ blender: HKBBlenderFields,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float,
        weights: [Float]? = nil
    ) -> BehaviorPose {
        let threshold = bound.float(
            "m_referencePoseWeightThreshold",
            or: blender
                .referencePoseWeightThreshold
        )
        let children = blendChildren(
            blender, bound: bound, depth: depth, deltaTime: deltaTime, weights: weights
        )
        let masked = children.map {
            BehaviorPoseMath.MaskedChild(
                pose: $0.pose, weight: $0.weight, boneWeights: $0.boneWeights
            )
        }
        let full = masked.filter { !$0.pose.isAdditive }
        var blended = full.isEmpty
            ? BehaviorPoseMath.unchanged(boneCount: graph.skeleton.referencePose.count)
            : BehaviorPoseMath.blend(
                masked: full, fallback: graph.skeleton.restPose, referenceThreshold: threshold
            )
        // Each additive child adds on top at its own weight, after the normal children.
        for layer in masked where layer.pose.isAdditive {
            blended = BehaviorPoseMath.adding(
                layer.pose,
                to: blended,
                weight: layer.weight(ofBone:)
            )
        }
        blended.rootMotion = BehaviorPoseMath
            .blend(
                children: children.map { ($0.pose, $0.motionWeight) },
                fallback: graph.skeleton.restPose
            )
            .rootMotion
        return blended
    }

    /// Evaluates every contributing child. A synced blender runs its leader first, so the
    /// others can follow its phase; each result returns to its own index, keeping blend order.
    func blendChildren(
        _ blender: HKBBlenderFields,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float,
        weights override: [Float]? = nil
    ) -> [BehaviorBlendChild] {
        noteBlendGaps(blender)
        let entries = blender.children.map { $0.flatMap(blenderEntry(at:)) }
        let parametric = blender.flags & BehaviorBlenderFlag.parametricBlend != 0
        let weights = override.flatMap { $0.count == entries.count ? $0 : nil }
            ?? childWeights(blender, entries: entries, bound: bound)
        let keepsAll = blender.flags & BehaviorBlenderFlag
            .dontDeactivateChildrenWithZeroWeights != 0
        let active = entries.indices.filter { index in
            entries[index] != nil
                && (weights[index] != 0 || keepsAll || index == blender.indexOfSyncMasterChild)
        }
        let synced = blender.flags & BehaviorBlenderFlag.sync != 0
            || active.contains(blender.indexOfSyncMasterChild)
        var cycle = BehaviorSharedCycle()
        if synced, active.count > 1 {
            cycle = sharedCycle(blender, entries: entries, weights: weights, active: active)
        }
        let outer = graph.pendingClipPhase
        let outerMute = graph.nodeMemory.mutesClipAnnotations
        defer {
            graph.pendingClipPhase = outer
            graph.nodeMemory.mutesClipAnnotations = outerMute
        }
        var results = [BehaviorBlendChild?](repeating: nil, count: entries.count)
        for index in cycle.order(active) {
            guard let entry = entries[index] else { continue }
            graph.nodeMemory
                .mutesClipAnnotations = outerMute || (cycle.leader != nil && index != cycle.leader)
            results[index] = blendChild(
                entry,
                weights: (pose: weights[index], motion: parametric ? weights[index] : 1),
                depth: depth,
                deltaTime: deltaTime * cycle.rate(of: index)
            )
            if index == cycle.leader {
                let phase = graph.clipPlayback.clipPhase(under: entry.child.generator)
                graph.pendingClipPhase = phase.map { ($0, false) } ?? outer
            }
        }
        return results.compactMap(\.self)
    }

    private func blenderEntry(at target: HKXPointerTarget) -> BehaviorBlenderEntry? {
        guard
            let node = graph.compiledNode(at: target),
            let child = node.object as? HKBBlenderGeneratorChild
        else { return nil }
        graph.markReached(target)
        var entry = BehaviorBlenderEntry(child: child, bound: graph.boundValues(of: node))
        entry.characterWeights = graph.characterBoneWeights(of: node, path: "boneWeights")
        return entry
    }

    /// Each child's share of the blend. A parametric blender reads `m_weight` as the
    /// child's place along `m_blendParameter` instead.
    private func childWeights(
        _ blender: HKBBlenderFields,
        entries: [BehaviorBlenderEntry?],
        bound: [String: BehaviorVariableValue]
    ) -> [Float] {
        let authored = entries.map { entry in
            entry.map { $0.bound.float("m_weight", or: $0.child.weight) } ?? .nan
        }
        let smooths = blender.flags & BehaviorBlenderFlag.smoothGeneratorWeights != 0
        guard blender.flags & BehaviorBlenderFlag.parametricBlend != 0 else {
            return authored.map { weight in
                let clamped = weight.isNaN ? 0 : min(max(weight, 0), 1)
                return smooths ? BehaviorParametricBlend.smoothed(clamped) : clamped
            }
        }
        let low = bound.float("m_minCyclicBlendParameter", or: blender.minCyclicBlendParameter)
        let high = bound.float("m_maxCyclicBlendParameter", or: blender.maxCyclicBlendParameter)
        let isCyclic = blender.flags & BehaviorBlenderFlag.isParametricBlendCyclic != 0
        let weights = BehaviorParametricBlend.weights(
            positions: authored,
            parameter: bound.float("m_blendParameter", or: blender.blendParameter),
            cyclic: isCyclic && low < high ? low ... high : nil
        )
        return smooths ? weights.map(BehaviorParametricBlend.smoothed) : weights
    }

    /// The leader and the cycle length the active children share: the sync master's
    /// cycle, or else the weighted mean of the children's cycles.
    private func sharedCycle(
        _ blender: HKBBlenderFields,
        entries: [BehaviorBlenderEntry?],
        weights: [Float],
        active: [Int]
    ) -> BehaviorSharedCycle {
        var durations: [Int: Float] = [:]
        for index in active {
            durations[index] = graph.clipPlayback
                .clipCycleDuration(under: entries[index]?.child.generator)
        }
        let master = blender.indexOfSyncMasterChild
        let heaviest = active.max { (weights[$0], -$0) < (weights[$1], -$1) }
        let leader = active.contains(master) ? master : heaviest
        var shared: Float?
        if let leader, active.contains(master) {
            shared = durations[leader]
        } else {
            let known = active.filter { durations[$0] != nil }
            let total = known.reduce(Float(0)) { $0 + weights[$1] }
            let sum = known.reduce(Float(0)) { $0 + weights[$1] * (durations[$1] ?? 0) }
            shared = total > 0 ? sum / total : nil
        }
        return BehaviorSharedCycle(leader: leader, durations: durations, shared: shared)
    }

    /// A child played as a blend input. The motion weight folds a parametric weight into the
    /// root travel, so only the children around the parameter move the actor.
    private func blendChild(
        _ entry: BehaviorBlenderEntry,
        weights: (pose: Float, motion: Float),
        depth: Int,
        deltaTime: Float
    ) -> BehaviorBlendChild {
        let (weight, motionScale) = (weights.pose, weights.motion)
        let child = entry.child
        return BehaviorBlendChild(
            pose: graph.evaluateGenerator(at: child.generator, depth: depth, deltaTime: deltaTime),
            weight: weight,
            motionWeight: motionScale * entry.bound.float(
                "m_worldFromModelWeight", or: child.worldFromModelWeight
            ),
            boneWeights: entry.characterWeights ?? graph.blenders.boneWeights(at: child.boneWeights)
        )
    }

    private func noteBlendGaps(_ blender: HKBBlenderFields) {
        if blender.subtractLastChild {
            graph.tally.note(.blenderSubtractLastChild)
        }
    }
}

/// How fast each synced child plays: its own cycle over the shared one, so all loops
/// end together. An unsynced blender plays every child at 1.
nonisolated struct BehaviorSharedCycle {
    var leader: Int?
    var durations: [Int: Float] = [:]
    var shared: Float?

    func rate(of index: Int) -> Float {
        guard let shared, shared > 0, let own = durations[index], own > 0 else { return 1 }
        return own / shared
    }

    /// The leader first, then the rest in declared order.
    func order(_ active: [Int]) -> [Int] {
        guard let leader else { return active }
        return [leader] + active.filter { $0 != leader }
    }
}

nonisolated extension BehaviorGraphInstance.Blenders {
    /// The decoded per-bone mask at `target`, honouring a binding on it, or nil
    /// when the child carries none.
    func boneWeights(at target: HKXPointerTarget?) -> [Float]? {
        guard
            let target,
            let array = graph.object(at: target, as: HKBBoneWeightArray.self),
            !array.boneWeights.isEmpty
        else { return nil }
        graph.markReached(target)
        return array.boneWeights
    }

    /// Blends two poses. When only one is additive, both become full poses first.
    func blendFull(_ lhs: BehaviorPose, _ rhs: BehaviorPose, weight: Float) -> BehaviorPose {
        guard lhs.isAdditive != rhs.isAdditive else {
            return BehaviorPoseMath.blend(lhs, rhs, weight: weight)
        }
        return BehaviorPoseMath.blend(
            graph.skeleton.absolute(lhs),
            graph.skeleton.absolute(rhs),
            weight: weight
        )
    }
}
