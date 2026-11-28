// Where a ray first meets the land: steps along the ray, sampling the height field,
// then halves the last step until the point lies on the ground.

import simd

nonisolated public struct TerrainRayHit: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let normal: SIMD3<Float>
    /// Travel along the ray from its origin.
    public let distance: Float

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, distance: Float) {
        self.position = position
        self.normal = normal
        self.distance = distance
    }
}

nonisolated public enum TerrainRayMarch {
    /// About one land quad's eighth, so a ray cannot cross a ridge between two samples.
    public static let step: Float = 16
    static let refinementCount = 10

    /// Nil when the ray stays above the land within `reach`, or starts below it.
    public static func firstHit(
        from origin: SIMD3<Float>, along direction: SIMD3<Float>, within reach: Float,
        sample: (SIMD2<Float>) -> TerrainGroundSample?
    ) -> TerrainRayHit? {
        guard reach > 0, simd_length_squared(direction) > 1e-8 else { return nil }
        let ray = simd_normalize(direction)
        func below(_ travel: Float) -> TerrainGroundSample? {
            let point = origin + ray * travel
            guard let ground = sample(SIMD2(point.x, point.y)), point.z <= ground.height
            else { return nil }
            return ground
        }
        guard below(0) == nil else { return nil }
        var clear: Float = 0
        var travel = min(step, reach)
        while below(travel) == nil {
            guard travel < reach else { return nil }
            clear = travel
            travel = min(travel + step, reach)
        }
        for _ in 0 ..< refinementCount {
            let middle = (clear + travel) / 2
            if below(middle) == nil {
                clear = middle
            } else {
                travel = middle
            }
        }
        let point = origin + ray * travel
        guard let ground = sample(SIMD2(point.x, point.y)) else { return nil }
        return TerrainRayHit(
            position: SIMD3(point.x, point.y, ground.height), normal: ground.normal,
            distance: travel
        )
    }
}
