// Engine-side geometry types, decoupled from any on-disk layout (AGENTS.md
// reverse-engineering discipline). Producer: NIF scene flatten
// (NIFFile.model()); consumer: the static-mesh render path (todo 2.6).

import Foundation
import simd

/// One drawable chunk: vertex arrays + triangle indices in mesh-local space,
/// the transform into model space, and a material slot resolved against the
/// owning Model. Attribute arrays are either empty or vertex-count sized.
nonisolated package struct Mesh {
    package let name: String?
    /// Mesh-local -> model-root transform (column vectors, `M * v`; see
    /// docs/decisions/coordinates.md).
    package let transform: float4x4
    package let positions: [SIMD3<Float>]
    package let normals: [SIMD3<Float>]
    package let tangents: [SIMD3<Float>]
    package let bitangents: [SIMD3<Float>]
    package let uvs: [SIMD2<Float>]
    /// RGBA in [0, 1].
    package let colors: [SIMD4<Float>]
    /// Flat triangle list, three indices per triangle, all < positions.count.
    package let indices: [UInt16]
    /// Index into the owning `Model.materials`.
    package let materialSlot: Int
    /// Nil for rigid geometry. Skinned meshes carry four influences per
    /// vertex + bind-pose matrices for the GPU skinning path.
    package let skinning: MeshSkinning?

    package init(
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

nonisolated package struct MeshSkinning {
    package let weights: [SIMD4<Float>]
    package let boneIndices: [SIMD4<UInt16>]
    package let bindPoseMatrices: [float4x4]
    /// Skin-instance bone order. Empty for synthetic/legacy meshes that do
    /// not opt into runtime animation.
    package let boneNames: [String]
    /// Gamebryo palette composition: rootParentToSkin * currentBone * skinToBone.
    package let rootParentToSkin: float4x4
    package let skinToBoneMatrices: [float4x4]

    package init(
        weights: [SIMD4<Float>],
        boneIndices: [SIMD4<UInt16>],
        bindPoseMatrices: [float4x4],
        boneNames: [String] = [],
        rootParentToSkin: float4x4 = matrix_identity_float4x4,
        skinToBoneMatrices: [float4x4] = []
    ) {
        self.weights = weights
        self.boneIndices = boneIndices
        self.bindPoseMatrices = bindPoseMatrices
        self.boneNames = boneNames
        self.rootParentToSkin = rootParentToSkin
        self.skinToBoneMatrices = skinToBoneMatrices
    }
}

/// One loaded asset: every drawable mesh plus the materials they index.
/// Shapes referencing the same shader/alpha property blocks share one
/// material slot (instancing-ready, todo 2.7).
nonisolated package struct Model {
    package let meshes: [Mesh]
    package let materials: [Material]
    /// Shapes dropped during flatten (unsupported or empty) — surfaced so scene
    /// build (todo 2.7) can report skips instead of silently thinning
    /// geometry.
    package let skippedShapeCount: Int

    package init(meshes: [Mesh], materials: [Material], skippedShapeCount: Int) {
        self.meshes = meshes
        self.materials = materials
        self.skippedShapeCount = skippedShapeCount
    }
}
