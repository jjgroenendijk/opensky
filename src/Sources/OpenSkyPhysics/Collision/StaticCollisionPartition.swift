// Broadphase leaves for large triangle soups. A placed NIF shape remains one
// logical stats entry, while spatial chunks keep capsule narrowphase from
// retesting an entire building or landscape collision mesh per substep.

public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyFormatsMesh
public import simd

nonisolated public struct StaticCollisionPartition: Sendable {
    public let geometry: NIFCollisionGeometry
    public let localBounds: ModelBounds
}

nonisolated public struct StaticCollisionPartitionResult: Sendable {
    public let partitions: [StaticCollisionPartition]
    public let failureCount: Int
}

nonisolated extension StaticCollisionShape {
    private static let maximumTrianglesPerLeaf = 64

    public static func placed(
        reference: FormID,
        transform: float4x4,
        geometry: NIFCollisionGeometry,
        material: FormID? = nil
    ) -> [StaticCollisionShape] {
        placed(
            reference: reference,
            transform: transform,
            partitions: partitions(for: geometry).partitions,
            material: material
        )
    }

    /// Partitioning is spatial, and a NIF shape carries one material for all of
    /// its geometry, so every leaf a shape splits into inherits that material.
    public static func placed(
        reference: FormID,
        transform: float4x4,
        partitions: [StaticCollisionPartition],
        material: FormID? = nil
    ) -> [StaticCollisionShape] {
        partitions.map { partition in
            StaticCollisionShape(
                reference: reference,
                transform: transform,
                geometry: partition.geometry,
                bounds: partition.localBounds.transformed(by: transform),
                material: material
            )
        }
    }

    public static func partitions(
        for geometry: NIFCollisionGeometry
    ) -> StaticCollisionPartitionResult {
        guard
            case let .triangleSoup(vertices, indices) = geometry,
            indices.count / 3 > maximumTrianglesPerLeaf
        else {
            return singlePartition(geometry)
        }
        var partitions: [StaticCollisionPartition] = []
        var failureCount = 0
        for group in spatialGroups(vertices: vertices, indices: indices) {
            if let partition = trianglePartition(vertices: vertices, indices: group) {
                partitions.append(partition)
            } else {
                failureCount += 1
            }
        }
        return StaticCollisionPartitionResult(
            partitions: partitions,
            failureCount: failureCount
        )
    }

    /// Splits the triangles at the median of their centres along the longest axis, again
    /// and again, until each group fits a leaf. A leaf then covers a compact area, so a
    /// query near one point meets few leaves and few triangles. A split by file order gave
    /// leaves that each spanned the whole mesh.
    static func spatialGroups(vertices: [SIMD3<Float>], indices: [UInt32]) -> [[UInt32]] {
        var triangles: [(Int, SIMD3<Float>)] = []
        var broken: [UInt32] = []
        for triangle in 0 ..< indices.count / 3 {
            let corners = indices[triangle * 3 ..< triangle * 3 + 3]
            guard corners.allSatisfy({ Int($0) < vertices.count }) else {
                broken += corners
                continue
            }
            let centre = corners.reduce(SIMD3<Float>.zero) { $0 + vertices[Int($1)] } / 3
            triangles.append((triangle, centre))
        }
        var groups: [[UInt32]] = []
        var pending = triangles.isEmpty ? [] : [triangles[...]]
        while let group = pending.popLast() {
            guard group.count > maximumTrianglesPerLeaf else {
                groups.append(group.flatMap { indices[$0.0 * 3 ..< $0.0 * 3 + 3] })
                continue
            }
            var low = group.first?.1 ?? .zero
            var high = low
            for (_, centre) in group {
                low = simd_min(low, centre)
                high = simd_max(high, centre)
            }
            let size = high - low
            let axis = size.x >= size.y && size.x >= size.z ? 0 : (size.y >= size.z ? 1 : 2)
            let sorted = group.sorted { ($0.1[axis], $0.0) < ($1.1[axis], $1.0) }
            let middle = sorted.count / 2
            pending.append(sorted[middle...])
            pending.append(sorted[..<middle])
        }
        // A triangle with a vertex past the end makes its own leaf, which then fails.
        let leaf = maximumTrianglesPerLeaf * 3
        return groups + stride(from: 0, to: broken.count, by: leaf).map {
            Array(broken[$0 ..< min($0 + leaf, broken.count)])
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
    ) -> StaticCollisionPartitionResult {
        guard let bounds = localBounds(geometry) else {
            return StaticCollisionPartitionResult(partitions: [], failureCount: 1)
        }
        return StaticCollisionPartitionResult(
            partitions: [StaticCollisionPartition(geometry: geometry, localBounds: bounds)],
            failureCount: 0
        )
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
