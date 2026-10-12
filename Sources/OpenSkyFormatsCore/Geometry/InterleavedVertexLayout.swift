// The interleaved vertex the static-mesh shaders read. It lives below the renderer so the
// mesh cache can store vertices in this layout, ready to read straight into a GPU buffer.

import simd

/// float3 position, float3 normal, float2 texcoord, float4 color: 48 bytes of tightly
/// packed floats, not simd-aligned.
nonisolated public enum InterleavedVertexLayout: Sendable {
    public static let positionOffset = 0
    public static let normalOffset = 12
    public static let texcoordOffset = 24
    public static let colorOffset = 32
    public static let stride = 48

    /// Defaults for a mesh that omits an array: +Z normal (world up,
    /// docs/decisions/coordinates.md), origin UV, opaque white color.
    public static let defaultNormal = SIMD3<Float>(0, 0, 1)
    public static let defaultColor = SIMD4<Float>(1, 1, 1, 1)

    /// Packs a mesh's attribute arrays. Each array is empty or vertex-count sized.
    public static func interleave(_ mesh: Mesh) -> [Float] {
        var floats: [Float] = []
        floats.reserveCapacity(mesh.positions.count * stride / MemoryLayout<Float>.size)
        let normals = mesh.normals.isEmpty ? smoothNormals(of: mesh) : mesh.normals
        for index in mesh.positions.indices {
            let position = mesh.positions[index]
            let normal = index < normals.count ? normals[index] : defaultNormal
            let uv = index < mesh.uvs.count ? mesh.uvs[index] : .zero
            let color = index < mesh.colors.count ? mesh.colors[index] : defaultColor
            floats.append(contentsOf: [
                position.x, position.y, position.z,
                normal.x, normal.y, normal.z,
                uv.x, uv.y,
                color.x, color.y, color.z, color.w
            ])
        }
        return floats
    }

    /// Area-weighted vertex normals from the triangles. A model-space normal map
    /// shape stores none, and its shadow and fallback lighting still need one.
    public static func smoothNormals(of mesh: Mesh) -> [SIMD3<Float>] {
        var sums = [SIMD3<Float>](repeating: .zero, count: mesh.positions.count)
        for start in Swift.stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let corners = (0 ..< 3).map { Int(mesh.indices[start + $0]) }
            guard corners.allSatisfy(sums.indices.contains) else { continue }
            let edgeA = mesh.positions[corners[1]] - mesh.positions[corners[0]]
            let edgeB = mesh.positions[corners[2]] - mesh.positions[corners[0]]
            let face = simd_cross(edgeA, edgeB)
            for corner in corners {
                sums[corner] += face
            }
        }
        return sums.map { simd_length_squared($0) > 0 ? simd_normalize($0) : defaultNormal }
    }
}
