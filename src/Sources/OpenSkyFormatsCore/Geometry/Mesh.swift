// Engine-side geometry types, decoupled from any on-disk layout (AGENTS.md
// reverse-engineering discipline). Producer: NIF scene flatten
// (NIFFile.model()); consumer: the static-mesh render path.

import Foundation
public import simd

/// One drawable chunk: vertex arrays + triangle indices in mesh-local space,
/// the transform into model space, and a material slot resolved against the
/// owning Model. Attribute arrays are either empty or vertex-count sized.
nonisolated public struct Mesh: Sendable {
    public let name: String?
    /// Mesh-local -> model-root transform (column vectors, `M * v`; see
    /// docs/decisions/coordinates.md).
    public let transform: float4x4
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let tangents: [SIMD3<Float>]
    public let bitangents: [SIMD3<Float>]
    public let uvs: [SIMD2<Float>]
    /// RGBA in [0, 1].
    public let colors: [SIMD4<Float>]
    /// Flat triangle list, three indices per triangle, all < positions.count.
    public let indices: [UInt16]
    /// Index into the owning `Model.materials`.
    public let materialSlot: Int
    /// Nil for rigid geometry. Skinned meshes carry four influences per
    /// vertex + bind-pose matrices for the GPU skinning path.
    public let skinning: MeshSkinning?
    /// The index count of each detail level (`MeshLODLevels`); empty for one level.
    public let lodIndexCounts: [Int]
    /// The segment of an object LOD large-reference shape this piece came from; segment
    /// `k` holds the large references of one cell (docs/formats/lod.md).
    public let objectLODSegment: Int?

    public init(
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
        skinning: MeshSkinning? = nil,
        lodIndexCounts: [Int] = [],
        objectLODSegment: Int? = nil
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
        self.lodIndexCounts = lodIndexCounts
        self.objectLODSegment = objectLODSegment
    }
}

nonisolated public struct MeshSkinning: Sendable {
    public let weights: [SIMD4<Float>]
    public let boneIndices: [SIMD4<UInt16>]
    public let bindPoseMatrices: [float4x4]
    /// Skin-instance bone order. Empty for synthetic/legacy meshes that do
    /// not opt into runtime animation.
    public let boneNames: [String]
    /// Gamebryo palette composition: rootParentToSkin * currentBone * skinToBone.
    public let rootParentToSkin: float4x4
    public let skinToBoneMatrices: [float4x4]
    /// The dismember partitions over `Mesh.indices`; empty for a plain skin instance.
    public let bodyParts: [MeshBodyPart]

    public init(
        weights: [SIMD4<Float>],
        boneIndices: [SIMD4<UInt16>],
        bindPoseMatrices: [float4x4],
        boneNames: [String] = [],
        rootParentToSkin: float4x4 = matrix_identity_float4x4,
        skinToBoneMatrices: [float4x4] = [],
        bodyParts: [MeshBodyPart] = []
    ) {
        self.bodyParts = bodyParts
        self.weights = weights
        self.boneIndices = boneIndices
        self.bindPoseMatrices = bindPoseMatrices
        self.boneNames = boneNames
        self.rootParentToSkin = rootParentToSkin
        self.skinToBoneMatrices = skinToBoneMatrices
    }
}

/// One dismember partition: a body part ID (nif.xml `BSDismemberBodyPartType`, such as
/// 32 for the body) over a range of `Mesh.indices`, in index units.
nonisolated public struct MeshBodyPart: Equatable, Sendable {
    public let bodyPart: UInt16
    public let indices: Range<Int>

    public init(bodyPart: UInt16, indices: Range<Int>) {
        self.bodyPart = bodyPart
        self.indices = indices
    }
}

/// One loaded asset: every drawable mesh plus the materials they index.
/// Shapes referencing the same shader/alpha property blocks share one
/// material slot, ready for instancing.
nonisolated public struct Model: Sendable {
    public let meshes: [Mesh]
    public let materials: [Material]
    /// Shapes dropped during flatten (unsupported or empty) — surfaced so scene
    /// build can report skips instead of silently thinning
    /// geometry.
    public let skippedShapeCount: Int
    /// Editor-only shapes left out on purpose, as the game hides them.
    public let editorMarkerShapeCount: Int

    public init(
        meshes: [Mesh],
        materials: [Material],
        skippedShapeCount: Int,
        editorMarkerShapeCount: Int = 0
    ) {
        self.meshes = meshes
        self.materials = materials
        self.skippedShapeCount = skippedShapeCount
        self.editorMarkerShapeCount = editorMarkerShapeCount
    }
}
