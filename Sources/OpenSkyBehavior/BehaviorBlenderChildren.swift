// The children of one `hkbBlenderGenerator` update: their weights, authored or
// parametric, and the shared cycle of a synced blender, which plays every child at the
// speed that ends their loops together (docs/engine/behavior-clips.md#clip-synchronization).

import Foundation
import OpenSkyFormatsAnimation

/// One decoded `hkbBlenderGeneratorChild` with the values bound onto it.
nonisolated struct BehaviorBlenderEntry {
    let child: HKBBlenderGeneratorChild
    let bound: [String: BehaviorVariableValue]
}

nonisolated extension BehaviorGraphInstance {
    /// Evaluates every contributing child. A synced blender runs its leader first, so the
    /// others can follow its phase; each result returns to its own index, keeping blend order.
    func blendChildren(
        _ blender: HKBBlenderFields,
        bound: [String: BehaviorVariableValue],
        threshold: Float,
        depth: Int,
        deltaTime: Float
    ) -> [BehaviorBlendChild] {
        noteBlendGaps(blender)
        let entries = blender.children.map { $0.flatMap(blenderEntry(at:)) }
        let parametric = blender.flags & BehaviorBlenderFlag.parametricBlend != 0
        let weights = childWeights(blender, entries: entries, bound: bound)
        let active = entries.indices.filter { entries[$0] != nil && weights[$0] > threshold }
        let synced = blender.flags & BehaviorBlenderFlag.sync != 0
            || active.contains(blender.indexOfSyncMasterChild)
        var cycle = BehaviorSharedCycle()
        if synced, active.count > 1 {
            cycle = sharedCycle(blender, entries: entries, weights: weights, active: active)
        }
        let outer = pendingClipPhase
        let outerMute = mutesClipAnnotations
        defer {
            pendingClipPhase = outer
            mutesClipAnnotations = outerMute
        }
        var results = [BehaviorBlendChild?](repeating: nil, count: entries.count)
        for index in cycle.order(active) {
            guard let entry = entries[index] else { continue }
            mutesClipAnnotations = outerMute || (cycle.leader != nil && index != cycle.leader)
            results[index] = blendChild(
                entry,
                weight: weights[index],
                motionScale: parametric ? weights[index] : 1,
                depth: depth,
                deltaTime: deltaTime * cycle.rate(of: index)
            )
            if index == cycle.leader {
                pendingClipPhase = clipPhase(under: entry.child.generator).map { ($0, false) }
                    ?? outer
            }
        }
        return results.compactMap(\.self)
    }

    private func blenderEntry(at target: HKXPointerTarget) -> BehaviorBlenderEntry? {
        guard
            let node = compiledNode(at: target),
            let child = node.object as? HKBBlenderGeneratorChild
        else { return nil }
        markReached(target)
        return BehaviorBlenderEntry(child: child, bound: boundValues(of: node))
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
        guard blender.flags & BehaviorBlenderFlag.parametricBlend != 0 else {
            return authored.map { $0.isNaN ? 0 : $0 }
        }
        let low = bound.float("m_minCyclicBlendParameter", or: blender.minCyclicBlendParameter)
        let high = bound.float("m_maxCyclicBlendParameter", or: blender.maxCyclicBlendParameter)
        let isCyclic = blender.flags & BehaviorBlenderFlag.isParametricBlendCyclic != 0
        return BehaviorParametricBlend.weights(
            positions: authored,
            parameter: bound.float("m_blendParameter", or: blender.blendParameter),
            cyclic: isCyclic && low < high ? low ... high : nil
        )
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
            durations[index] = clipCycleDuration(under: entries[index]?.child.generator)
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

    /// A child played as a blend input. `motionScale` folds a parametric weight into the
    /// root travel, so only the children around the parameter move the actor.
    private func blendChild(
        _ entry: BehaviorBlenderEntry,
        weight: Float,
        motionScale: Float,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorBlendChild {
        let child = entry.child
        return BehaviorBlendChild(
            pose: evaluateGenerator(at: child.generator, depth: depth, deltaTime: deltaTime),
            weight: weight,
            motionWeight: motionScale * entry.bound.float(
                "m_worldFromModelWeight", or: child.worldFromModelWeight
            ),
            boneWeights: boneWeights(at: child.boneWeights)
        )
    }

    private func noteBlendGaps(_ blender: HKBBlenderFields) {
        if blender.flags & BehaviorBlenderFlag.smoothGeneratorWeights != 0 {
            tally.note(.blenderSmoothWeightsIgnored)
        }
        if blender.subtractLastChild {
            tally.note(.blenderSubtractLastChild)
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
