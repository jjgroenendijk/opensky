// The Gamebryo bone-palette composition, kept away from Metal so tests can
// check it without a device:
//     palette[i] = rootParentToSkin * currentBone[i] * skinToBone[i]
// With the bind transform as current bone the factors cancel. Details:
// docs/formats/nif-skinning.md.

import simd

/// The metadata one skinned mesh needs to be re-posed at runtime, plus the
/// composition itself. Built once per mesh from `MeshSkinning`.
nonisolated public struct SkinningPalette: Sendable {
    /// Skin-instance bone order — the names a skeleton pose is matched by.
    public let boneNames: [String]
    public let rootParentToSkin: float4x4
    public let skinToBoneMatrices: [float4x4]
    /// The verified NIF bind palette, and the fallback for any bone the pose
    /// does not name.
    public let bindPoseMatrices: [float4x4]

    /// One composed pose: the palette to upload, and how many of its bones the
    /// pose actually named.
    public struct Posed: Sendable {
        public let matrices: [float4x4]
        public let matchedBoneCount: Int
    }

    public init(
        boneNames: [String],
        rootParentToSkin: float4x4,
        skinToBoneMatrices: [float4x4],
        bindPoseMatrices: [float4x4]
    ) {
        self.boneNames = boneNames
        self.rootParentToSkin = rootParentToSkin
        self.skinToBoneMatrices = skinToBoneMatrices
        self.bindPoseMatrices = bindPoseMatrices
    }

    /// Nil for a mesh that carries no runtime-pose metadata: a synthetic or
    /// legacy skin whose three arrays do not agree on a bone count cannot be
    /// re-posed, and a partial palette would be worse than none.
    public init?(_ skinning: MeshSkinning) {
        let boneCount = skinning.bindPoseMatrices.count
        guard
            skinning.boneNames.count == boneCount,
            skinning.skinToBoneMatrices.count == boneCount
        else { return nil }
        self.init(
            boneNames: skinning.boneNames,
            rootParentToSkin: skinning.rootParentToSkin,
            skinToBoneMatrices: skinning.skinToBoneMatrices,
            bindPoseMatrices: skinning.bindPoseMatrices
        )
    }

    /// Composes an animated skeleton-world pose, keyed by bone name, into a
    /// palette. Unmatched helper and NIF-only bones keep their bind matrix.
    public func posed(by transformsByName: [String: float4x4]) -> Posed {
        var matrices = bindPoseMatrices
        var matchedBoneCount = 0
        for index in boneNames.indices {
            guard let current = transformsByName[boneNames[index]] else { continue }
            matrices[index] = rootParentToSkin * current * skinToBoneMatrices[index]
            matchedBoneCount += 1
        }
        return Posed(matrices: matrices, matchedBoneCount: matchedBoneCount)
    }

    /// The skeleton bone each palette bone takes its pose from, or -1 when the
    /// skeleton does not name it. Built once per skeleton a mesh binds to.
    public func skeletonIndices(in bones: SkeletonBoneIndex) -> [Int] {
        boneNames.map { bones.index(of: $0) ?? -1 }
    }

    /// Composes `pose` into `matrices` in place through `skeletonIndices(in:)`.
    /// An unmapped or unposed bone keeps its bind matrix. Returns the matched count.
    public func pose(
        _ pose: SkeletonPose,
        through skeletonIndices: [Int],
        into matrices: inout [float4x4]
    ) -> Int {
        if matrices.count != bindPoseMatrices.count {
            matrices = bindPoseMatrices
        }
        var matchedBoneCount = 0
        for index in boneNames.indices {
            let source = index < skeletonIndices.count ? skeletonIndices[index] : -1
            guard source >= 0, source < pose.matrices.count else {
                matrices[index] = bindPoseMatrices[index]
                continue
            }
            matrices[index] = rootParentToSkin * pose.matrices[source] * skinToBoneMatrices[index]
            matchedBoneCount += 1
        }
        return matchedBoneCount
    }
}
