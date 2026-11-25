// A skin and its Havok skeleton can spell a bone in different case, as the
// chicken's `HEAD` and `Head`; the bone must still take the pose.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct SkinBoneNameCaseTests {
    private static let palette = SkinningPalette(
        boneNames: ["Pelvis", "HEAD"],
        rootParentToSkin: matrix_identity_float4x4,
        skinToBoneMatrices: [matrix_identity_float4x4, matrix_identity_float4x4],
        bindPoseMatrices: [matrix_identity_float4x4, matrix_identity_float4x4]
    )
    private static let moved = MatrixMath.translation(SIMD3(0, 200, 0))

    @Test
    func aSkeletonFindsABoneSpelledInOtherCase() {
        let bones = SkeletonBoneIndex(names: ["NPC Root", "Head", "head"])

        #expect(bones.index(of: "HEAD") == 1, "the first bone of any case")
        #expect(bones.index(of: "head") == 2, "an exact name comes first")
        #expect(bones.index(of: "Tail") == nil)
    }

    @Test
    func aSkinBoneTakesThePoseOfItsOtherCaseSkeletonBone() {
        let pose = SkeletonPose(
            bones: SkeletonBoneIndex(names: ["Pelvis", "Head"]),
            matrices: [matrix_identity_float4x4, Self.moved]
        )
        var matrices: [float4x4] = []
        let indices = Self.palette.skeletonIndices(in: pose.bones)

        let matched = Self.palette.pose(pose, through: indices, into: &matrices)

        #expect(matched == 2)
        #expect(matrices[1].columns.3 == SIMD4(0, 200, 0, 1))
    }

    @Test
    func aPoseByNameMatchesABoneSpelledInOtherCase() {
        let posed = Self.palette.posed(by: ["Pelvis": matrix_identity_float4x4, "Head": Self.moved])

        #expect(posed.matchedBoneCount == 2)
        #expect(posed.matrices[1].columns.3 == SIMD4(0, 200, 0, 1))
    }
}
