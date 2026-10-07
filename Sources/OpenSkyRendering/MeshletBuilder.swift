// Splits a triangle list into meshlets: small clusters a mesh shader threadgroup draws in
// one go, each with bounds an object shader can cull. See docs/rendering/mesh-shader-grass.md.

import simd

/// One cluster of a mesh. Its triangles index its own vertex list, which indexes the mesh.
nonisolated public struct Meshlet: Equatable, Sendable {
    public var vertexOffset: UInt32
    public var vertexCount: UInt32
    public var triangleOffset: UInt32
    public var triangleCount: UInt32
    /// A sphere around the meshlet's vertices, in mesh space.
    public var center: SIMD3<Float>
    public var radius: Float
    /// The average facing of the triangles. A camera in the cone's back half sees none of
    /// them when `coneCutoff` is above -1; -1 means the cone cannot cull.
    public var coneAxis: SIMD3<Float>
    public var coneCutoff: Float
}

/// The meshlets of one mesh and the two index lists they point into.
nonisolated public struct MeshletMesh: Equatable, Sendable {
    public var meshlets: [Meshlet] = []
    /// Mesh vertex indices, `vertexCount` per meshlet from its `vertexOffset`.
    public var vertexIndices: [UInt32] = []
    /// Three meshlet-local vertex indices per triangle, from `triangleOffset`.
    public var triangleIndices: [UInt8] = []

    public var triangleCount: Int {
        triangleIndices.count / 3
    }
}

nonisolated public enum MeshletBuilder {
    /// Apple's limits allow more. The GPU reserves this much output for every mesh
    /// threadgroup an object threadgroup starts, and 124 triangles ran out of memory.
    public static let maximumVertices = 64
    public static let maximumTriangles = 64

    /// Greedy in index order: a triangle that would overflow either limit starts a new
    /// meshlet. Triangles that name a vertex past `positions` are dropped.
    public static func build(indices: [UInt16], positions: [SIMD3<Float>]) -> MeshletMesh {
        var result = MeshletMesh()
        var current = OpenMeshlet()
        var triangle = 0
        while triangle + 2 < indices.count {
            let corners = (0 ..< 3).map { Int(indices[triangle + $0]) }
            triangle += 3
            guard corners.allSatisfy({ $0 < positions.count }) else { continue }
            if !current.fits(corners) {
                result.append(current, positions: positions)
                current = OpenMeshlet()
            }
            current.add(corners)
        }
        result.append(current, positions: positions)
        return result
    }
}

/// The meshlet being filled.
nonisolated private struct OpenMeshlet {
    var vertices: [Int] = []
    var localIndex: [Int: UInt8] = [:]
    var triangles: [UInt8] = []

    func fits(_ corners: [Int]) -> Bool {
        let added = Set(corners.filter { localIndex[$0] == nil }).count
        return vertices.count + added <= MeshletBuilder.maximumVertices
            && triangles.count / 3 < MeshletBuilder.maximumTriangles
    }

    mutating func add(_ corners: [Int]) {
        for corner in corners {
            if let local = localIndex[corner] {
                triangles.append(local)
            } else {
                let local = UInt8(vertices.count)
                localIndex[corner] = local
                vertices.append(corner)
                triangles.append(local)
            }
        }
    }
}

nonisolated extension MeshletMesh {
    fileprivate mutating func append(_ open: OpenMeshlet, positions: [SIMD3<Float>]) {
        guard !open.triangles.isEmpty else { return }
        let points = open.vertices.map { positions[$0] }
        let low = points.reduce(points[0], simd_min)
        let high = points.reduce(points[0], simd_max)
        let center = (low + high) / 2
        let radius = points.map { simd_distance($0, center) }.max() ?? 0
        let normals = stride(from: 0, to: open.triangles.count, by: 3).map { start in
            let corner = { points[Int(open.triangles[start + $0])] }
            return simd_cross(corner(1) - corner(0), corner(2) - corner(0))
        }
        let (axis, cutoff) = Self.cone(normals)
        meshlets.append(Meshlet(
            vertexOffset: UInt32(vertexIndices.count), vertexCount: UInt32(points.count),
            triangleOffset: UInt32(triangleIndices.count / 3),
            triangleCount: UInt32(open.triangles.count / 3),
            center: center, radius: radius, coneAxis: axis, coneCutoff: cutoff
        ))
        vertexIndices += open.vertices.map(UInt32.init)
        triangleIndices += open.triangles
    }

    /// The normal cone: its axis is the mean facing, its cutoff the sine of the widest
    /// angle between the axis and a triangle's facing. -1 when the facings spread too far.
    private static func cone(_ normals: [SIMD3<Float>]) -> (SIMD3<Float>, Float) {
        let units = normals.compactMap { normal -> SIMD3<Float>? in
            let length = simd_length(normal)
            return length > .ulpOfOne ? normal / length : nil
        }
        let sum = units.reduce(SIMD3<Float>.zero, +)
        guard simd_length(sum) > .ulpOfOne else { return (SIMD3(0, 0, 1), -1) }
        let axis = simd_normalize(sum)
        let narrowest = units.map { simd_dot($0, axis) }.min() ?? 1
        guard narrowest > 0.1 else { return (axis, -1) }
        return (axis, (1 - narrowest * narrowest).squareRoot())
    }
}
