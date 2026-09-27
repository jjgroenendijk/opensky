// The static half of the dynamic narrowphase, split from DynamicBodyContacts
// for the type-length limit (issue #193): how deep a world-space sphere sits
// inside one placed collision shape, for every geometry the static world holds,
// and which way that shape's surface faces (issue #392).
//
// Documented in docs/engine/dynamic-bodies.md.

import simd

/// How a triangle's plane normal becomes a surface normal.
///
/// The rule this replaces oriented every normal toward the body's centre of
/// mass, on the premise that a convex body resting on a surface always has its
/// centre on the outside of it. Real data does not honour that premise. The
/// real-data probe found vanilla clutter whose decoded centre of mass sits
/// *below every vertex of its own collider*: the item then oriented the shelf's
/// top face downward, was driven through the shelf, and accelerated out of the
/// world. Any thin body sunk past its own half-thickness flips the same way.
/// Nothing about the body is a safe reference — the surface has to speak for
/// itself.
nonisolated enum DynamicSurfaceOrientation {
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
    static func of(_ geometry: NIFCollisionGeometry) -> Self {
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
    func transformed(by matrix: float4x4) -> Self {
        switch self {
        case .winding:
            .winding
        case let .outward(interior):
            .outward(from: DynamicCollisionMath.transform(interior, by: matrix))
        }
    }

    /// Turns a triangle's raw winding normal into its surface normal.
    func oriented(_ normal: SIMD3<Float>, at vertex: SIMD3<Float>) -> SIMD3<Float> {
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
    static func penetration(
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

    /// Signed sphere-versus-triangle against a triangle already prepared for
    /// the query, for the caller that has one point and one triangle.
    static func nearestSurface(
        of point: SIMD3<Float>,
        radius: Float,
        triangle: CollisionTriangle,
        orientation: DynamicSurfaceOrientation,
        recovery: Float = recoveryDepth
    ) -> (distance: Float, penetration: DynamicPenetration?)? {
        DynamicSurfaceTriangle(triangle, orientation: orientation)?.surface(
            of: point, radius: radius, recovery: recovery
        )
    }
}

/// One triangle with everything that does not depend on the sample already
/// worked out: its bounds and its oriented surface normal.
///
/// A step over a real interior asks the same triangle about every sample of
/// every nearby body, so anything computed inside that loop is computed twenty
/// times over for one answer. Hoisting the cross product, the normalisation,
/// the facing decision and the bounds out of it is most of what took the
/// measured step from tens of milliseconds to something a frame can afford.
nonisolated struct DynamicSurfaceTriangle {
    let triangle: CollisionTriangle
    /// The surface normal, already facing the way the shape's own rule says.
    let normal: SIMD3<Float>
    let lower: SIMD3<Float>
    let upper: SIMD3<Float>

    /// Nil for a degenerate triangle, which has no surface to speak of.
    init?(_ triangle: CollisionTriangle, orientation: DynamicSurfaceOrientation) {
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
    ///
    /// - Parameter nearerThan: the best distance the caller has already found
    ///   for this sample. The distance from the sample to the triangle's own
    ///   *plane* is a lower bound on the distance to the triangle, and it costs
    ///   one dot product against the closest-point query's several dozen
    ///   operations, so a triangle that cannot beat the incumbent is dismissed
    ///   before that query runs. The pruning is exact: nothing that could have
    ///   won is skipped.
    /// - Returns: nil when this triangle is out of range or cannot be the
    ///   nearest. A non-nil answer with no penetration still matters — it is how
    ///   a near surface saying "outside" vetoes a far one saying "deep inside".
    func surface(
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
