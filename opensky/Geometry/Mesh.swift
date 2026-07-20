// Engine-side geometry types, decoupled from any on-disk layout (AGENTS.md
// reverse-engineering discipline). Producer: NIF scene flatten
// (NIFFile.model()); consumer: the static-mesh render path (todo 2.6).

import Foundation
import simd

/// One drawable chunk: vertex arrays + triangle indices in mesh-local space,
/// the transform into model space, and a material slot resolved against the
/// owning Model. Attribute arrays are either empty or vertex-count sized.
nonisolated struct Mesh {
    let name: String?
    /// Mesh-local -> model-root transform (column vectors, `M * v`; see
    /// docs/decisions/coordinates.md).
    let transform: float4x4
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let tangents: [SIMD3<Float>]
    let bitangents: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    /// RGBA in [0, 1].
    let colors: [SIMD4<Float>]
    /// Flat triangle list, three indices per triangle, all < positions.count.
    let indices: [UInt16]
    /// Index into the owning `Model.materials`.
    let materialSlot: Int
    /// Nil for rigid geometry. Skinned meshes carry four influences per
    /// vertex + bind-pose matrices for the GPU skinning path.
    let skinning: MeshSkinning?

    init(
        name: String?,
        transform: float4x4,
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        tangents: [SIMD3<Float>],
        bitangents: [SIMD3<Float>],
        uvs: [SIMD2<Float>],
        colors: [SIMD4<Float>],
        indices: [UInt16],
        materialSlot: Int,
        skinning: MeshSkinning? = nil
    ) {
        self.name = name
        self.transform = transform
        self.positions = positions
        self.normals = normals
        self.tangents = tangents
        self.bitangents = bitangents
        self.uvs = uvs
        self.colors = colors
        self.indices = indices
        self.materialSlot = materialSlot
        self.skinning = skinning
    }
}

nonisolated struct MeshSkinning {
    let weights: [SIMD4<Float>]
    let boneIndices: [SIMD4<UInt16>]
    let bindPoseMatrices: [float4x4]
}

/// One loaded asset: every drawable mesh plus the materials they index.
/// Shapes referencing the same shader/alpha property blocks share one
/// material slot (instancing-ready, todo 2.7).
nonisolated struct Model {
    let meshes: [Mesh]
    let materials: [Material]
    /// Shapes dropped during flatten (unsupported or empty) — surfaced so scene
    /// build (todo 2.7) can report skips instead of silently thinning
    /// geometry.
    let skippedShapeCount: Int
}
