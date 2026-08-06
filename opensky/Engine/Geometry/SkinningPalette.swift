// The Gamebryo bone-palette composition, kept away from Metal so it can be
// checked against hand-computed matrices without a device (issue #354).
//
// A skinned NIF authors its vertices in skin space and hands the engine two
// halves of the bind pose: `rootParentToSkin`, which carries skin space back to
// the skeleton root's parent, and one `skinToBone` per bone, which carries skin
// space into that bone. A pose is written by putting the bone's *current*
// transform between them:
//
//     palette[i] = rootParentToSkin * currentBone[i] * skinToBone[i]
//
// Feed it the bone's own bind transform and the three factors cancel, so the
// palette comes out as the bind palette and the mesh does not move. That
// cancellation is the property the unit test pins, because it is exactly what
// fails when the current transform is composed in a convention the bind halves
// were not authored in: the mesh tears rather than standing still.

import simd

/// The metadata one skinned mesh needs to be re-posed at runtime, plus the
/// composition itself. Built once per mesh from `MeshSkinning`.
nonisolated struct SkinningPalette {
    /// Skin-instance bone order — the names a skeleton pose is matched by.
    let boneNames: [String]
    let rootParentToSkin: float4x4
    let skinToBoneMatrices: [float4x4]
    /// The verified NIF bind palette, and the fallback for any bone the pose
    /// does not name.
    let bindPoseMatrices: [float4x4]

    /// One composed pose: the palette to upload, and how many of its bones the
    /// pose actually named.
    struct Posed {
        let matrices: [float4x4]
        let matchedBoneCount: Int
    }

    init(
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
    init?(_ skinning: MeshSkinning) {
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
    func posed(by transformsByName: [String: float4x4]) -> Posed {
        var matrices = bindPoseMatrices
        var matchedBoneCount = 0
        for index in boneNames.indices {
            guard let current = transformsByName[boneNames[index]] else { continue }
            matrices[index] = rootParentToSkin * current * skinToBoneMatrices[index]
            matchedBoneCount += 1
        }
        return Posed(matrices: matrices, matchedBoneCount: matchedBoneCount)
    }
}
