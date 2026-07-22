// Simple precipitation roof occlusion over the existing resident static-
// collision BVH: broadphase a vertical segment, then test its upward ray
// against exact triangle/convex/box faces. Curved shapes use their world AABB;
// vanilla architectural roofs resolve through triangle collections.

import simd

nonisolated enum PrecipitationRoofOcclusion {
    static let maximumDistance: Float = 4096

    static func isOccluded(
        above origin: SIMD3<Float>,
        maximumDistance: Float = maximumDistance,
        query: WalkController.CollisionQuery
    ) -> Bool {
        guard maximumDistance > 0 else { return false }
        let epsilon: Float = 0.5
        let bounds = ModelBounds(
            min: origin - SIMD3(epsilon, epsilon, 0),
            max: origin + SIMD3(epsilon, epsilon, maximumDistance)
        )
        return query(bounds).contains {
            $0.upwardRayHitDistance(from: origin, maximumDistance: maximumDistance) != nil
        }
    }
}

nonisolated extension StaticCollisionShape {
    fileprivate func upwardRayHitDistance(
        from origin: SIMD3<Float>,
        maximumDistance: Float
    ) -> Float? {
        switch geometry {
        case let .triangleSoup(vertices, indices):
            triangleHit(
                vertices: vertices, indices: indices,
                origin: origin, maximumDistance: maximumDistance
            )
        case let .convexVertices(vertices, indices):
            triangleHit(
                vertices: vertices, indices: indices,
                origin: origin, maximumDistance: maximumDistance
            )
        case let .box(halfExtents):
            triangleHit(
                vertices: CapsuleWorldCollider.boxVertices(halfExtents),
                indices: CapsuleWorldCollider.boxIndices,
                origin: origin,
                maximumDistance: maximumDistance
            )
        case .sphere, .capsule:
            verticalBoundsHit(from: origin, maximumDistance: maximumDistance)
        }
    }

    private func triangleHit(
        vertices: [SIMD3<Float>],
        indices: [UInt32],
        origin: SIMD3<Float>,
        maximumDistance: Float
    ) -> Float? {
        var closest: Float?
        for offset in stride(from: 0, to: indices.count - indices.count % 3, by: 3) {
            let raw = [indices[offset], indices[offset + 1], indices[offset + 2]]
            guard raw.allSatisfy({ Int($0) < vertices.count }) else { continue }
            let triangle = raw.map { worldPoint(vertices[Int($0)]) }
            guard let distance = upwardTriangleHit(origin: origin, triangle: triangle) else {
                continue
            }
            guard distance <= maximumDistance else { continue }
            closest = min(closest ?? distance, distance)
        }
        return closest
    }

    private func verticalBoundsHit(from origin: SIMD3<Float>, maximumDistance: Float) -> Float? {
        guard
            origin.x >= bounds.min.x, origin.x <= bounds.max.x,
            origin.y >= bounds.min.y, origin.y <= bounds.max.y,
            bounds.max.z >= origin.z
        else { return nil }
        let distance = max(bounds.min.z - origin.z, 0)
        return distance <= maximumDistance ? distance : nil
    }

    private func worldPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let value = transform * SIMD4(point, 1)
        return SIMD3(value.x, value.y, value.z)
    }

    private func upwardTriangleHit(
        origin: SIMD3<Float>,
        triangle: [SIMD3<Float>]
    ) -> Float? {
        let direction = SIMD3<Float>(0, 0, 1)
        let edge1 = triangle[1] - triangle[0]
        let edge2 = triangle[2] - triangle[0]
        let cross = simd_cross(direction, edge2)
        let determinant = simd_dot(edge1, cross)
        guard abs(determinant) > 1e-6 else { return nil }
        let inverse = 1 / determinant
        let relative = origin - triangle[0]
        let u = inverse * simd_dot(relative, cross)
        guard u >= 0, u <= 1 else { return nil }
        let relativeCross = simd_cross(relative, edge1)
        let v = inverse * simd_dot(direction, relativeCross)
        guard v >= 0, u + v <= 1 else { return nil }
        let distance = inverse * simd_dot(edge2, relativeCross)
        return distance > 1e-4 ? distance : nil
    }
}
