// Walkable surface probe for bounded capsule step offset. Vertical faces are
// excluded by slope; triangle winding is treated two-sided for collision.

import simd

nonisolated extension CapsuleWorldCollider {
    func stepSupportHeight(
        at position: SIMD2<Float>,
        minimumHeight: Float,
        maximumHeight: Float,
        query: CandidateQuery
    ) -> Float? {
        let epsilon: Float = 0.01
        let bounds = ModelBounds(
            min: SIMD3(position.x - epsilon, position.y - epsilon, minimumHeight),
            max: SIMD3(position.x + epsilon, position.y + epsilon, maximumHeight)
        )
        return query(bounds)
            .compactMap { $0.walkableSupportHeight(at: position) }
            .filter { $0 >= minimumHeight - epsilon && $0 <= maximumHeight + epsilon }
            .max()
    }
}

nonisolated extension StaticCollisionShape {
    fileprivate func walkableSupportHeight(at position: SIMD2<Float>) -> Float? {
        let surfaces: (vertices: [SIMD3<Float>], indices: [UInt32])
        switch geometry {
        case let .triangleSoup(vertices, indices):
            surfaces = (vertices, indices)
        case let .convexVertices(vertices, hullIndices):
            surfaces = (vertices, hullIndices)
        case let .box(halfExtents):
            surfaces = (
                CapsuleWorldCollider.boxVertices(halfExtents),
                CapsuleWorldCollider.boxIndices
            )
        case .sphere, .capsule:
            return nil
        }
        var result: Float?
        for offset in stride(
            from: 0,
            to: surfaces.indices.count - surfaces.indices.count % 3,
            by: 3
        ) {
            let first = transformed(surfaces.vertices[Int(surfaces.indices[offset])])
            let second = transformed(surfaces.vertices[Int(surfaces.indices[offset + 1])])
            let third = transformed(surfaces.vertices[Int(surfaces.indices[offset + 2])])
            guard
                let height = Self.walkableTriangleHeight(
                    at: position,
                    first: first,
                    second: second,
                    third: third
                ) else { continue }
            result = max(result ?? height, height)
        }
        return result
    }

    private func transformed(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let value = transform * SIMD4<Float>(point, 1)
        return SIMD3(value.x, value.y, value.z)
    }

    fileprivate static func walkableTriangleHeight(
        at point: SIMD2<Float>,
        first: SIMD3<Float>,
        second: SIMD3<Float>,
        third: SIMD3<Float>
    ) -> Float? {
        let normal = simd_cross(second - first, third - first)
        let length = simd_length(normal)
        guard length > Float.ulpOfOne else { return nil }
        let minimumUp = cosf(MatrixMath.radians(fromDegrees: WalkController.maximumSlopeDegrees))
        guard abs(normal.z / length) >= minimumUp else { return nil }

        let edgeA = SIMD2<Float>(second.x - first.x, second.y - first.y)
        let edgeB = SIMD2<Float>(third.x - first.x, third.y - first.y)
        let relative = point - SIMD2<Float>(first.x, first.y)
        let determinant = edgeA.x * edgeB.y - edgeA.y * edgeB.x
        guard abs(determinant) > Float.ulpOfOne else { return nil }
        let firstWeight = (relative.x * edgeB.y - relative.y * edgeB.x) / determinant
        let secondWeight = (edgeA.x * relative.y - edgeA.y * relative.x) / determinant
        let epsilon: Float = 1e-4
        guard
            firstWeight >= -epsilon,
            secondWeight >= -epsilon,
            firstWeight + secondWeight <= 1 + epsilon
        else { return nil }
        return first.z
            + firstWeight * (second.z - first.z)
            + secondWeight * (third.z - first.z)
    }
}
