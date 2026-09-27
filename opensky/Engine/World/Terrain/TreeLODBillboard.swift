// Engine geometry for traditional Skyrim tree LOD: two double-sided planes
// intersecting at 90 degrees, using one LST rectangle in the worldspace atlas.

import simd

nonisolated enum TreeLODBillboard {
    static func model(type: TreeLODType, atlasPath: String) -> Model {
        let halfWidth = type.width * 0.5
        let bottom = type.uvMax.y
        let top = type.uvMin.y
        let left = type.uvMin.x
        let right = type.uvMax.x
        let positions: [SIMD3<Float>] = [
            SIMD3(-halfWidth, 0, 0), SIMD3(halfWidth, 0, 0),
            SIMD3(halfWidth, 0, type.height), SIMD3(-halfWidth, 0, type.height),
            SIMD3(0, -halfWidth, 0), SIMD3(0, halfWidth, 0),
            SIMD3(0, halfWidth, type.height), SIMD3(0, -halfWidth, type.height)
        ]
        let uvs = [
            SIMD2(left, bottom), SIMD2(right, bottom),
            SIMD2(right, top), SIMD2(left, top),
            SIMD2(left, bottom), SIMD2(right, bottom),
            SIMD2(right, top), SIMD2(left, top)
        ]
        let mesh = Mesh(
            name: "tree-lod-\(type.index)",
            transform: matrix_identity_float4x4,
            positions: positions,
            normals: [],
            tangents: [],
            bitangents: [],
            uvs: uvs,
            colors: [],
            indices: [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7],
            materialSlot: 0
        )
        let material = Material(
            diffuseTexture: atlasPath,
            normalTexture: nil,
            uvOffset: .zero,
            uvScale: SIMD2(1, 1),
            alpha: 1,
            glossiness: 0,
            specularColor: .zero,
            specularStrength: 0,
            doubleSided: true,
            alphaBlend: false,
            alphaTestThreshold: 0.5
        )
        return Model(meshes: [mesh], materials: [material], skippedShapeCount: 0)
    }
}
