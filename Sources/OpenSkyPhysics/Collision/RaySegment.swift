// A finite ray for walking a bounds tree. The box test is the slab test: the ray
// is inside the box where it is inside all three pairs of planes.

import OpenSkyFormatsCore
import simd

nonisolated public struct RaySegment: Sendable {
    /// Boxes grow by this much, so a hit on a face the box only touches still counts.
    public static let padding: Float = 0.01

    public let origin: SIMD3<Float>
    /// Unit length.
    public let direction: SIMD3<Float>
    public let maximumDistance: Float

    public init(origin: SIMD3<Float>, direction: SIMD3<Float>, maximumDistance: Float) {
        self.origin = origin
        self.direction = direction
        self.maximumDistance = maximumDistance
    }

    /// The distance where the segment enters `bounds`, zero from inside, nil when
    /// it misses the box.
    public func entry(into bounds: ModelBounds) -> Float? {
        var near: Float = 0
        var far = maximumDistance
        for axis in 0 ..< 3 {
            let lower = bounds.min[axis] - Self.padding
            let upper = bounds.max[axis] + Self.padding
            let start = origin[axis]
            let step = direction[axis]
            if step == 0 {
                guard start >= lower, start <= upper else { return nil }
                continue
            }
            let first = (lower - start) / step
            let second = (upper - start) / step
            near = max(near, min(first, second))
            far = min(far, max(first, second))
            guard near <= far else { return nil }
        }
        return near
    }
}
