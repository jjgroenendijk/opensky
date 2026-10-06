// Sphere and capsule casts against placed geometry: a ray against the geometry grown
// by the radius. Exact for spheres and capsules, early (never late) for triangles and
// hulls, which is safe for hit volumes and tunneling. Ties break as in
// `InteractionRaycaster`. See docs/engine/dynamic-narrowphase.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import simd

/// A shape cast along a straight path.
nonisolated public struct ShapeSweepQuery: Sendable {
    /// The swept shape's start pose. For a capsule these are the two segment
    /// ends; for a sphere pass the same point twice.
    public let first: SIMD3<Float>
    public let second: SIMD3<Float>
    public let radius: Float
    /// Direction of travel; normalized on use, so an unnormalized vector is
    /// accepted.
    public let direction: SIMD3<Float>
    public let maximumDistance: Float

    public static func sphere(
        center: SIMD3<Float>,
        radius: Float,
        direction: SIMD3<Float>,
        maximumDistance: Float
    ) -> ShapeSweepQuery {
        ShapeSweepQuery(
            first: center,
            second: center,
            radius: radius,
            direction: direction,
            maximumDistance: maximumDistance
        )
    }

    public static func capsule(
        first: SIMD3<Float>,
        second: SIMD3<Float>,
        radius: Float,
        direction: SIMD3<Float>,
        maximumDistance: Float
    ) -> ShapeSweepQuery {
        ShapeSweepQuery(
            first: first,
            second: second,
            radius: radius,
            direction: direction,
            maximumDistance: maximumDistance
        )
    }

    /// The AABB the whole sweep occupies, which is what the broadphase is asked
    /// for before any narrowphase runs.
    public var bounds: ModelBounds {
        let travel = normalizedDirection * maximumDistance
        let extent = SIMD3<Float>(repeating: radius)
        let lower = simd_min(simd_min(first, second), simd_min(first, second) + travel)
        let upper = simd_max(simd_max(first, second), simd_max(first, second) + travel)
        return ModelBounds(min: lower - extent, max: upper + extent)
    }

    public var normalizedDirection: SIMD3<Float> {
        let length = simd_length(direction)
        return length > Float.ulpOfOne ? direction / length : SIMD3(0, 0, -1)
    }
}

/// Where a sweep first touched something.
nonisolated public struct ShapeSweepHit: Equatable, Sendable {
    public let reference: FormID
    /// Travel distance along the sweep direction at first touch. Zero means the
    /// shape already overlapped at the start pose.
    public let distance: Float
    /// Point on the obstacle, in world space.
    public let position: SIMD3<Float>
    /// Surface normal pointing back toward the swept shape.
    public let normal: SIMD3<Float>
    /// True when the start pose already overlapped, so `distance` is not a
    /// distance travelled. A tunneling guard treats this as "already stuck".
    public let startsOverlapping: Bool
    /// The MATT type of the surface touched, or nil where the shape names none.
    public var material: FormID?
}

/// One overlap of the swept shape at a sampled travel distance.
nonisolated private struct SweepOverlap {
    let reference: FormID
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
    let material: FormID?
}

nonisolated public enum ShapeSweeper: Sendable {
    /// Steps taken along the sweep before the first touching step is bisected.
    /// The coarse pass costs one overlap test each; the bisection then converges
    /// on the touch distance to well inside the solver's penetration slop.
    public static let sampleCount = 24
    /// Bisection rounds after the first touching sample.
    public static let refinementCount = 12
    private static let epsilon: Float = 1e-5

    /// First hit along `query`, or nil where the sweep is clear.
    public static func firstHit(
        query: ShapeSweepQuery,
        shapes: [StaticCollisionShape]
    ) -> ShapeSweepHit? {
        guard
            query.radius >= 0, query.maximumDistance > 0,
            query.first.isFiniteVector, query.second.isFiniteVector
        else { return nil }
        if let overlap = overlap(query: query, travel: 0, shapes: shapes) {
            return ShapeSweepHit(
                reference: overlap.reference,
                distance: 0,
                position: overlap.position,
                normal: overlap.normal,
                startsOverlapping: true,
                material: overlap.material
            )
        }
        let step = query.maximumDistance / Float(sampleCount)
        for sample in 1 ... sampleCount {
            let travel = step * Float(sample)
            guard overlap(query: query, travel: travel, shapes: shapes) != nil else { continue }
            let distance = refine(query: query, clear: travel - step, hit: travel, shapes: shapes)
            guard let touch = overlap(query: query, travel: distance, shapes: shapes) else {
                continue
            }
            return ShapeSweepHit(
                reference: touch.reference,
                distance: distance,
                position: touch.position,
                normal: touch.normal,
                startsOverlapping: false,
                material: touch.material
            )
        }
        return nil
    }

    /// Bisects between a clear travel distance and a touching one.
    private static func refine(
        query: ShapeSweepQuery,
        clear: Float,
        hit: Float,
        shapes: [StaticCollisionShape]
    ) -> Float {
        var low = clear
        var high = hit
        for _ in 0 ..< refinementCount {
            let middle = (low + high) * 0.5
            if overlap(query: query, travel: middle, shapes: shapes) != nil {
                high = middle
            } else {
                low = middle
            }
        }
        return high
    }

    /// Deepest overlap of the swept shape, displaced by `travel`, against any
    /// shape. Ties break on the lower reference so the answer is deterministic.
    private static func overlap(
        query: ShapeSweepQuery,
        travel: Float,
        shapes: [StaticCollisionShape]
    ) -> SweepOverlap? {
        let offset = query.normalizedDirection * travel
        let first = query.first + offset
        let second = query.second + offset
        let samples = first == second ? [first] : [first, second]
        var best: SweepOverlap?
        var bestDepth = Float.zero
        for shape in shapes {
            for sample in samples {
                guard
                    let hit = DynamicBodyContacts.penetration(
                        of: sample, radius: query.radius, shape: shape
                    ), hit.depth > epsilon
                else { continue }
                let replaces = best.map { current in
                    hit.depth > bestDepth + epsilon
                        || (abs(hit.depth - bestDepth) <= epsilon
                            && shape.reference.rawValue < current.reference.rawValue)
                } ?? true
                guard replaces else { continue }
                bestDepth = hit.depth
                best = SweepOverlap(
                    reference: shape.reference,
                    position: sample - hit.normal * (query.radius - hit.depth),
                    normal: hit.normal,
                    material: shape.material
                )
            }
        }
        return best
    }
}
