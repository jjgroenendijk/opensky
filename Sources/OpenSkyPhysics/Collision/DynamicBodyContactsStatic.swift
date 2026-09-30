// The static half of the dynamic narrowphase: how deep a world-space sphere sits
// inside one placed collision shape, and which way that shape's surface faces.
// See docs/engine/dynamic-narrowphase.md.

import OpenSkyFormatsMesh
import simd

/// How a triangle's plane normal becomes a surface normal. The surface decides,
/// not the body: some vanilla clutter has its decoded center of mass below every
/// collider vertex, so orienting toward the center fails.
nonisolated public enum DynamicSurfaceOrientation: Sendable {
    /// Trust the winding the file carries. Vanilla wound its collision
    /// triangles front face outward, which the probe confirms over a whole
    /// interior's architecture and furniture: reading the winding straight took
    /// the farmhouse from half its clutter falling out of the world to none of
    /// it.
    case winding
    /// Orient away from a point known to be inside the shape. A box's vertices
    /// straddle its own origin and a convex hull's straddle its centroid, so
    /// for those two the interior point is exact — and their triangle
    /// connectivity is derived by this engine rather than authored, so unlike a
    /// soup they carry no winding worth trusting.
    case outward(from: SIMD3<Float>)

    /// The rule one placed shape's triangles are read under, in that shape's
    /// own local space.
    public static func of(_ geometry: NIFCollisionGeometry) -> Self {
        switch geometry {
        case let .convexVertices(vertices, _):
            .outward(from: Self.centroid(of: vertices))
        case .box:
            .outward(from: .zero)
        case .triangleSoup, .sphere, .capsule:
            .winding
        }
    }

    /// The same rule expressed in world space, for the query that places a
    /// shape's triangles before testing them.
    public func transformed(by matrix: float4x4) -> Self {
        switch self {
        case .winding:
            .winding
        case let .outward(interior):
            .outward(from: DynamicCollisionMath.transform(interior, by: matrix))
        }
    }

    /// Turns a triangle's raw winding normal into its surface normal.
    public func oriented(_ normal: SIMD3<Float>, at vertex: SIMD3<Float>) -> SIMD3<Float> {
        guard case let .outward(interior) = self else { return normal }
        return simd_dot(normal, interior - vertex) > 0 ? -normal : normal
    }

    private static func centroid(of vertices: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !vertices.isEmpty else { return .zero }
        return vertices.reduce(SIMD3<Float>.zero, +) / Float(vertices.count)
    }
}

nonisolated extension DynamicBodyContacts {
    /// How deep a world sphere sits inside one placed static shape.
    public static func penetration(
        of point: SIMD3<Float>,
        radius: Float,
        shape: StaticCollisionShape
    ) -> DynamicPenetration? {
        let orientation = DynamicSurfaceOrientation.of(shape.geometry)
            .transformed(by: shape.transform)
        switch shape.geometry {
        case let .triangleSoup(vertices, indices),
             let .convexVertices(vertices, indices):
            return triangleSoupPenetration(
                of: point,
                radius: radius,
                soup: PlacedTriangleSoup(
                    vertices: vertices, indices: indices, transform: shape.transform
                ),
                orientation: orientation
            )
        case let .box(halfExtents):
            return triangleSoupPenetration(
                of: point,
                radius: radius,
                soup: PlacedTriangleSoup(
                    vertices: CapsuleWorldCollider.boxVertices(halfExtents),
                    indices: CapsuleWorldCollider.boxIndices,
                    transform: shape.transform
                ),
                orientation: orientation
            )
        case let .sphere(shapeRadius):
            let scaled = shapeRadius * DynamicCollisionMath.maximumScale(of: shape.transform)
            let origin = DynamicCollisionMath.transform(.zero, by: shape.transform)
            return DynamicCollisionVolume
                .radial(first: origin, second: origin, radius: scaled)
                .penetration(of: point, radius: radius)
        case let .capsule(first, second, shapeRadius):
            let scaled = shapeRadius * DynamicCollisionMath.maximumScale(of: shape.transform)
            return DynamicCollisionVolume.radial(
                first: DynamicCollisionMath.transform(first, by: shape.transform),
                second: DynamicCollisionMath.transform(second, by: shape.transform),
                radius: scaled
            ).penetration(of: point, radius: radius)
        }
    }

    private static func triangleSoupPenetration(
        of point: SIMD3<Float>,
        radius: Float,
        soup: PlacedTriangleSoup,
        orientation: DynamicSurfaceOrientation
    ) -> DynamicPenetration? {
        let vertices = soup.vertices
        let indices = soup.indices
        var nearest: (distance: Float, penetration: DynamicPenetration?)?
        let end = indices.count - indices.count % 3
        for offset in stride(from: 0, to: end, by: 3) {
            let first = Int(indices[offset])
            let second = Int(indices[offset + 1])
            let third = Int(indices[offset + 2])
            guard first < vertices.count, second < vertices.count, third < vertices.count else {
                continue
            }
            let triangle = CollisionTriangle(
                first: DynamicCollisionMath.transform(vertices[first], by: soup.transform),
                second: DynamicCollisionMath.transform(vertices[second], by: soup.transform),
                third: DynamicCollisionMath.transform(vertices[third], by: soup.transform)
            )
            guard
                let surface = DynamicSurfaceTriangle(triangle, orientation: orientation),
                let hit = surface.surface(
                    of: point,
                    radius: radius,
                    recovery: recoveryDepth,
                    nearerThan: nearest?.distance ?? .greatestFiniteMagnitude
                )
            else { continue }
            nearest = hit
        }
        return nearest?.penetration
    }
}

/// One triangle with its bounds and oriented surface normal worked out in
/// advance. Hoisting this out of the per-sample loop is most of the measured
/// speedup.
nonisolated public struct DynamicSurfaceTriangle: Sendable {
    public let triangle: CollisionTriangle
    /// The surface normal, already facing the way the shape's own rule says.
    public let normal: SIMD3<Float>
    public let lower: SIMD3<Float>
    public let upper: SIMD3<Float>

    /// Nil for a degenerate triangle, which has no surface to speak of.
    public init?(_ triangle: CollisionTriangle, orientation: DynamicSurfaceOrientation) {
        let raw = simd_cross(
            triangle.second - triangle.first,
            triangle.third - triangle.first
        )
        guard simd_length_squared(raw) > Float.ulpOfOne else { return nil }
        self.triangle = triangle
        normal = orientation.oriented(simd_normalize(raw), at: triangle.first)
        lower = simd_min(simd_min(triangle.first, triangle.second), triangle.third)
        upper = simd_max(simd_max(triangle.first, triangle.second), triangle.third)
    }

    /// How far one sample sits from this triangle, and the penetration if it is
    /// behind the front face by less than `radius`.
    /// - Parameter nearerThan: the best distance found so far. The plane distance is
    ///   a cheap lower bound, so a triangle that cannot win is skipped exactly.
    /// - Returns: nil when out of range or not nearest. A non-nil answer with no
    ///   penetration lets a near "outside" veto a far "deep inside".
    public func surface(
        of point: SIMD3<Float>,
        radius: Float,
        recovery: Float,
        nearerThan best: Float = .greatestFiniteMagnitude
    ) -> (distance: Float, penetration: DynamicPenetration?)? {
        let slack = radius + recovery
        guard
            point.x >= lower.x - slack, point.x <= upper.x + slack,
            point.y >= lower.y - slack, point.y <= upper.y + slack,
            point.z >= lower.z - slack, point.z <= upper.z + slack
        else { return nil }
        let separation = simd_dot(normal, point - triangle.first)
        guard abs(separation) <= slack, abs(separation) < best else { return nil }
        let closest = CapsuleWorldCollider.closestPoint(on: triangle, to: point)
        // Distance to the triangle itself bounds the contact: past the recovery
        // depth the sample is nowhere near this piece of geometry, whatever the
        // infinite plane says.
        let distance = simd_distance(point, closest)
        guard distance <= slack, distance < best else { return nil }
        guard separation < radius else { return (distance: distance, penetration: nil) }
        return (
            distance: distance,
            penetration: DynamicPenetration(normal: normal, depth: radius - separation)
        )
    }
}
