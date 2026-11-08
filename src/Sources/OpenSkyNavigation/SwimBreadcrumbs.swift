// The player's recent swim path, kept as points a follower can swim along where no
// water navmesh leads to the player. See docs/engine/navigation.md.

import simd

nonisolated public struct SwimBreadcrumbs: Equatable, Sendable {
    /// A new point once the player swam this far from the last one.
    public static let spacing: Float = 128
    public static let capacity = 64
    /// A follower joins the trail at a point this close to it.
    public static let joinReach: Float = 1024
    /// The trail serves a target this close to its newest point.
    public static let targetReach: Float = 512

    public private(set) var points: [SIMD3<Float>] = []

    public init() {}

    /// Drops a point while the player swims. Leaving the water keeps the trail, so a
    /// follower still on the far bank can swim after the player.
    public mutating func record(_ feet: SIMD3<Float>, isSwimming: Bool) {
        guard isSwimming else { return }
        if let last = points.last, simd_distance(last, feet) < Self.spacing {
            return
        }
        points.append(feet)
        if points.count > Self.capacity {
            points.removeFirst(points.count - Self.capacity)
        }
    }

    /// The trail from the point nearest `start` on to `target`, or nil when the trail
    /// does not lead there or starts too far away.
    public func trail(from start: SIMD3<Float>, to target: SIMD3<Float>) -> [SIMD3<Float>]? {
        guard
            let newest = points.last, simd_distance(newest, target) <= Self.targetReach,
            let nearest = points.indices.min(by: {
                simd_distance(points[$0], start) < simd_distance(points[$1], start)
            }),
            simd_distance(points[nearest], start) <= Self.joinReach
        else { return nil }
        return Array(points[nearest...]) + [target]
    }
}
