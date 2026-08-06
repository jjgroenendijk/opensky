// The static half of the dynamic narrowphase, split from DynamicBodyContacts
// for the type-length limit (issue #193): how deep a world-space sphere sits
// inside one placed collision shape, for every geometry the static world holds.
//
// Documented in docs/engine/dynamic-bodies.md.

import simd

nonisolated extension DynamicBodyContacts {
    /// How deep a world sphere sits inside one placed static shape.
    static func penetration(
        of point: SIMD3<Float>,
        radius: Float,
        shape: StaticCollisionShape,
        center: SIMD3<Float>
    ) -> DynamicPenetration? {
        switch shape.geometry {
        case let .triangleSoup(vertices, indices),
             let .convexVertices(vertices, indices):
            return triangleSoupPenetration(
                of: point,
                radius: radius,
                soup: PlacedTriangleSoup(
                    vertices: vertices, indices: indices, transform: shape.transform
                ),
                center: center
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
                center: center
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
        center: SIMD3<Float>
    ) -> DynamicPenetration? {
        let vertices = soup.vertices
        let indices = soup.indices
        var nearest: (penetration: DynamicPenetration, distance: Float)?
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
                let hit = trianglePenetration(
                    of: point, radius: radius, triangle: triangle, center: center
                )
            else { continue }
            if hit.distance < (nearest?.distance ?? .greatestFiniteMagnitude) {
                nearest = hit
            }
        }
        return nearest?.penetration
    }

    /// Signed sphere-versus-triangle. The plane normal is oriented toward the
    /// body's centre so that a sample that has already crossed the surface is
    /// pushed back out rather than further in.
    /// - Returns: the penetration and how far the sample is from the triangle
    ///   itself. The distance is what ranks one triangle of a shape against
    ///   another: the nearest surface is the exit, not the deepest one. Ranking
    ///   by depth picks the far face of anything a sample is inside, which the
    ///   real-data probe caught as clutter authored just inside a shelf top
    ///   being expelled downward through the shelf and then falling out of the
    ///   world.
    static func trianglePenetration(
        of point: SIMD3<Float>,
        radius: Float,
        triangle: CollisionTriangle,
        center: SIMD3<Float>,
        recovery: Float = recoveryDepth
    ) -> (penetration: DynamicPenetration, distance: Float)? {
        // Cheap box reject first: the exact closest-point query below is the
        // expensive part of a step over real interior geometry, and most
        // triangles of a soup are nowhere near the sample.
        let slack = radius + recovery
        let lower = simd_min(simd_min(triangle.first, triangle.second), triangle.third)
        let upper = simd_max(simd_max(triangle.first, triangle.second), triangle.third)
        guard
            point.x >= lower.x - slack, point.x <= upper.x + slack,
            point.y >= lower.y - slack, point.y <= upper.y + slack,
            point.z >= lower.z - slack, point.z <= upper.z + slack
        else { return nil }
        let raw = simd_cross(
            triangle.second - triangle.first,
            triangle.third - triangle.first
        )
        guard simd_length_squared(raw) > Float.ulpOfOne else { return nil }
        let closest = CapsuleWorldCollider.closestPoint(on: triangle, to: point)
        // Distance to the triangle itself bounds the contact: past the recovery
        // depth the sample is nowhere near this piece of geometry, whatever the
        // infinite plane says.
        guard simd_distance(point, closest) <= radius + recovery else { return nil }
        var normal = simd_normalize(raw)
        if simd_dot(normal, center - triangle.first) < 0 {
            normal = -normal
        }
        let separation = simd_dot(normal, point - triangle.first)
        guard separation < radius else { return nil }
        return (
            penetration: DynamicPenetration(normal: normal, depth: radius - separation),
            distance: simd_distance(point, closest)
        )
    }
}
