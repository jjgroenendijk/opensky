// Runtime pose composition tests (milestone 6.4). Synthetic engine values
// only; no game assets.

@testable import opensky
import simd
import Testing

struct SkeletonPoseMathTests {
    private static let identityPose = HKABonePose(
        translation: .zero,
        rotation: simd_quatf(angle: 0, axis: SIMD3(0, 0, 1)),
        scale: SIMD3(repeating: 1)
    )

    @Test func composesParentChildWorldMatrices() throws {
        let skeleton = HKASkeleton(
            name: "rig",
            bones: [
                HKABone(name: "root", lockTranslation: false),
                HKABone(name: "child", lockTranslation: false)
            ],
            parentIndices: [-1, 0],
            referencePose: [Self.identityPose, Self.identityPose]
        )
        let world = try SkeletonPoseMath.worldMatrices(
            skeleton: skeleton,
            samples: [
                HKABoneTransformSample(
                    boneIndex: 0,
                    pose: HKABonePose(
                        translation: SIMD3(10, 0, 0),
                        rotation: simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)),
                        scale: SIMD3(repeating: 1)
                    )
                ),
                HKABoneTransformSample(
                    boneIndex: 1,
                    pose: HKABonePose(
                        translation: SIMD3(2, 0, 0),
                        rotation: Self.identityPose.rotation,
                        scale: SIMD3(repeating: 1)
                    )
                )
            ]
        )

        #expect(simd_distance(world[0].columns.3, SIMD4(10, 0, 0, 1)) < 1e-5)
        #expect(simd_distance(world[1].columns.3, SIMD4(10, 2, 0, 1)) < 1e-5)
    }

    @Test func unsampledBoneKeepsReferencePose() throws {
        let reference = HKABonePose(
            translation: SIMD3(0, 3, 0),
            rotation: Self.identityPose.rotation,
            scale: SIMD3(repeating: 1)
        )
        let skeleton = HKASkeleton(
            name: "rig",
            bones: [HKABone(name: "root", lockTranslation: false)],
            parentIndices: [-1],
            referencePose: [reference]
        )
        let world = try SkeletonPoseMath.worldMatrices(skeleton: skeleton, samples: [])
        #expect(world[0].columns.3 == SIMD4(0, 3, 0, 1))
    }

    @Test func rejectsParentCycle() {
        let skeleton = HKASkeleton(
            name: "bad",
            bones: [
                HKABone(name: "a", lockTranslation: false),
                HKABone(name: "b", lockTranslation: false)
            ],
            parentIndices: [1, 0],
            referencePose: [Self.identityPose, Self.identityPose]
        )
        #expect(throws: SkeletonPoseError.self) {
            try SkeletonPoseMath.worldMatrices(skeleton: skeleton, samples: [])
        }
    }
}
