// Broadphase leaves for large triangle soups. A placed NIF shape remains one
// logical stats entry, while spatial chunks keep capsule narrowphase from
// retesting an entire building or landscape collision mesh per substep.

import simd

nonisolated struct StaticCollisionPartition {
    let geometry: NIFCollisionGeometry
    let localBounds: ModelBounds
}

nonisolated extension StaticCollisionShape {
    private static let maximumTrianglesPerLeaf = 64

    static func placed(
        reference: FormID,
        transform: float4x4,
        geometry: NIFCollisionGeometry
    ) -> [StaticCollisionShape] {
        placed(
            reference: reference,
            transform: transform,
            partitions: partitions(for: geometry)
        )
    }

    static func placed(
        reference: FormID,
        transform: float4x4,
        partitions: [StaticCollisionPartition]
    ) -> [StaticCollisionShape] {
        partitions.map { partition in
            StaticCollisionShape(
                reference: reference,
                transform: transform,
                geometry: partition.geometry,
                bounds: partition.localBounds.transformed(by: transform)
            )
        }
    }

    static func partitions(for geometry: NIFCollisionGeometry) -> [StaticCollisionPartition] {
        guard case let .triangleSoup(vertices, indices) = geometry else {
            return singlePartition(geometry)
        }
        guard indices.count / 3 > maximumTrianglesPerLeaf else {
            return singlePartition(geometry)
        }
        return stride(from: 0, to: indices.count, by: maximumTrianglesPerLeaf * 3)
            .compactMap { start in
                let end = min(start + maximumTrianglesPerLeaf * 3, indices.count)
                return trianglePartition(
                    vertices: vertices,
                    indices: Array(indices[start ..< end])
                )
            }
    }

    private static func trianglePartition(
        vertices: [SIMD3<Float>],
        indices: [UInt32]
    ) -> StaticCollisionPartition? {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false
        for index in indices where Int(index) < vertices.count {
            minimum = simd_min(minimum, vertices[Int(index)])
            maximum = simd_max(maximum, vertices[Int(index)])
            found = true
        }
        guard found else { return nil }
        return StaticCollisionPartition(
            geometry: .triangleSoup(vertices: vertices, indices: indices),
            localBounds: ModelBounds(min: minimum, max: maximum)
        )
    }

    private static func singlePartition(
        _ geometry: NIFCollisionGeometry
    ) -> [StaticCollisionPartition] {
        guard let bounds = localBounds(geometry) else { return [] }
        return [StaticCollisionPartition(geometry: geometry, localBounds: bounds)]
    }

    private static func localBounds(_ geometry: NIFCollisionGeometry) -> ModelBounds? {
        switch geometry {
        case let .triangleSoup(vertices, _), let .convexVertices(vertices, _):
            ModelBounds.containing(vertices)
        case let .box(halfExtents):
            ModelBounds(min: -halfExtents, max: halfExtents)
        case let .sphere(radius):
            ModelBounds(min: SIMD3(repeating: -radius), max: SIMD3(repeating: radius))
        case let .capsule(first, second, radius):
            ModelBounds(
                min: simd_min(first, second) - SIMD3(repeating: radius),
                max: simd_max(first, second) + SIMD3(repeating: radius)
            )
        }
    }
}
