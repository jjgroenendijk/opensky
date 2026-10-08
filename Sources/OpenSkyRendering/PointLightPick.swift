// Per-draw point light choice without a sort. The renderer keeps one pick per
// lighting center until the scene changes, because cell lights do not move.

import simd

/// Up to `capacity` scene point lights by index, nearest first.
nonisolated public struct PointLightPick: Equatable, Sendable {
    public static let capacity = 8
    public fileprivate(set) var count = 0
    public fileprivate(set) var indices = SIMD8<Int32>(repeating: -1)
}

nonisolated extension RenderScene {
    /// Top-k by squared distance in fixed storage. Equal distances keep scene order.
    /// A scene with no more lights than `limit` keeps them all, in scene order.
    public func nearestPointLightPick(to position: SIMD3<Float>, limit: Int) -> PointLightPick {
        let limit = min(max(limit, 0), PointLightPick.capacity)
        var pick = PointLightPick()
        guard pointLights.count > limit else {
            pick.count = pointLights.count
            for index in pointLights.indices {
                pick.indices[index] = Int32(index)
            }
            return pick
        }
        guard limit > 0 else { return pick }
        var distances = SIMD8<Float>(repeating: .infinity)
        for (index, light) in pointLights.enumerated() {
            let distance = simd_length_squared(light.position - position)
            guard pick.count < limit || distance < distances[limit - 1] else { continue }
            var slot = min(pick.count, limit - 1)
            while slot > 0, distances[slot - 1] > distance {
                distances[slot] = distances[slot - 1]
                pick.indices[slot] = pick.indices[slot - 1]
                slot -= 1
            }
            distances[slot] = distance
            pick.indices[slot] = Int32(index)
            pick.count = min(pick.count + 1, limit)
        }
        return pick
    }
}
