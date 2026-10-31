// The parametric blend of `hkbBlenderGenerator` (flag 0x10): each child's `m_weight` is
// its place along `m_blendParameter`, and only the two children around the parameter
// play (docs/engine/behavior-clips.md#parametric-blend).

import Foundation

/// `hkbBlenderGenerator::BlenderFlags`, from the class reflection data.
nonisolated public enum BehaviorBlenderFlag {
    public static let sync = 0x1
    public static let smoothGeneratorWeights = 0x4
    public static let parametricBlend = 0x10
    public static let isParametricBlendCyclic = 0x20
}

nonisolated public enum BehaviorParametricBlend {
    /// One weight per child, summing to 1. `positions` are the children's places on the
    /// parameter axis; `cyclic` wraps the axis, such as a direction from 0 to 360.
    public static func weights(
        positions: [Float],
        parameter: Float,
        cyclic: ClosedRange<Float>? = nil
    ) -> [Float] {
        var weights = [Float](repeating: 0, count: positions.count)
        let order = positions.indices
            .filter { positions[$0].isFinite }
            .sorted { (positions[$0], $0) < (positions[$1], $1) }
        guard let first = order.first, let last = order.last else { return weights }
        guard parameter.isFinite, order.count > 1 else {
            weights[first] = 1
            return weights
        }
        if let cyclic, cyclic.upperBound > cyclic.lowerBound {
            return cyclicWeights(positions, order: order, parameter: parameter, range: cyclic)
        }
        if parameter <= positions[first] {
            weights[first] = 1
        } else if parameter >= positions[last] {
            weights[last] = 1
        } else {
            let end = order.firstIndex { positions[$0] > parameter } ?? order.count - 1
            share(&weights, begin: order[end - 1], end: order[end], at: parameter, in: positions)
        }
        return weights
    }

    private static func cyclicWeights(
        _ positions: [Float],
        order: [Int],
        parameter: Float,
        range: ClosedRange<Float>
    ) -> [Float] {
        var weights = [Float](repeating: 0, count: positions.count)
        let span = range.upperBound - range.lowerBound
        var wrapped = (parameter - range.lowerBound).truncatingRemainder(dividingBy: span)
        if wrapped < 0 {
            wrapped += span
        }
        wrapped += range.lowerBound
        if let end = order.firstIndex(where: { positions[$0] > wrapped }), end > 0 {
            share(&weights, begin: order[end - 1], end: order[end], at: wrapped, in: positions)
            return weights
        }
        // Past the last child or before the first: blend across the seam.
        guard let first = order.first, let last = order.last else { return weights }
        let begin = positions[last]
        let finish = positions[first] + span
        let point = wrapped < positions[first] ? wrapped + span : wrapped
        let fraction = finish > begin ? (point - begin) / (finish - begin) : 0
        weights[last] = 1 - min(max(fraction, 0), 1)
        weights[first] += min(max(fraction, 0), 1)
        return weights
    }

    private static func share(
        _ weights: inout [Float],
        begin: Int,
        end: Int,
        at parameter: Float,
        in positions: [Float]
    ) {
        let width = positions[end] - positions[begin]
        let fraction = width > 0 ? (parameter - positions[begin]) / width : 0
        weights[begin] = 1 - min(max(fraction, 0), 1)
        weights[end] = min(max(fraction, 0), 1)
    }
}
