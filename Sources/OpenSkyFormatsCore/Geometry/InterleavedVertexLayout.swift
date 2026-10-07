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
        for index in mesh.positions.indices {
            let position = mesh.positions[index]
            let normal = index < mesh.normals.count ? mesh.normals[index] : defaultNormal
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
}
