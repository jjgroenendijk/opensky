// How densely a mesh's texture coordinates cover its surface, for texture streaming.
// See docs/rendering/texture-streaming.md.

import simd

nonisolated public enum MeshUVDensity {
    /// UV units per world unit: the square root of the UV area over the world area,
    /// summed over the triangles. A card that maps the whole texture onto 64 units gives
    /// 1/64. Zero without UVs or area.
    public static func uvPerUnit(
        positions: [SIMD3<Float>], uvs: [SIMD2<Float>], indices: [UInt16]
    ) -> Float {
        guard uvs.count == positions.count else { return 0 }
        var worldArea: Float = 0
        var uvArea: Float = 0
        var index = 0
        while index + 2 < indices.count {
            let corners = (Int(indices[index]), Int(indices[index + 1]), Int(indices[index + 2]))
            index += 3
            guard max(corners.0, corners.1, corners.2) < positions.count else { continue }
            let edge1 = positions[corners.1] - positions[corners.0]
            let edge2 = positions[corners.2] - positions[corners.0]
            worldArea += simd_length(simd_cross(edge1, edge2))
            let uv1 = uvs[corners.1] - uvs[corners.0]
            let uv2 = uvs[corners.2] - uvs[corners.0]
            uvArea += abs(uv1.x * uv2.y - uv1.y * uv2.x)
        }
        guard worldArea > 0 else { return 0 }
        return (uvArea / worldArea).squareRoot()
    }
}
