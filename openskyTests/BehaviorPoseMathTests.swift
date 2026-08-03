// Behavior pose math (issue #187) against hand-computed values. Pure
// arithmetic on invented poses; no packfile, no install.

import Foundation
@testable import opensky
import simd
import Testing

struct BehaviorPoseMathTests {
    private let tolerance: Float = 1e-5

    private func pose(_ translationX: Float, scale: Float = 1) -> BehaviorPose {
        BehaviorPose(bones: [BehaviorFixture.bonePose(
            translation: SIMD3(translationX, 0, 0),
            scale: SIMD3(repeating: scale)
        )])
    }

    private func rotation(degrees: Float) -> simd_quatf {
        simd_quatf(angle: degrees * .pi / 180, axis: SIMD3(0, 0, 1))
    }

    @Test func blendsTwoPosesAtHandComputedWeight() {
        // Weights 3 and 1 place the result a quarter of the way to the second
        // child: 0 + (10 - 0) * (1 / (3 + 1)) = 2.5.
        let blended = BehaviorPoseMath.blend(
            children: [(pose(0), 3), (pose(10), 1)],
            fallback: pose(-1)
        )
        #expect(abs(blended.bones[0].translation.x - 2.5) < tolerance)
    }

    @Test func normalizedFoldEqualsTheWeightedAverage() {
        // (0 * 1 + 4 * 1 + 8 * 2) / 4 = 5, which the left-to-right fold must
        // reproduce exactly: mix(0, 4, 1/2) = 2, then mix(2, 8, 2/4) = 5.
        let blended = BehaviorPoseMath.blend(
            children: [(pose(0), 1), (pose(4), 1), (pose(8), 2)],
            fallback: pose(-1)
        )
        #expect(abs(blended.bones[0].translation.x - 5) < tolerance)
    }

    @Test func blendsScaleAlongsideTranslation() {
        let blended = BehaviorPoseMath.blend(
            children: [(pose(0, scale: 1), 1), (pose(0, scale: 3), 1)],
            fallback: pose(-1)
        )
        #expect(abs(blended.bones[0].scale.y - 2) < tolerance)
    }

    @Test func dropsNonPositiveWeightsAndFallsBackWhenNoneRemain() {
        let onlySecond = BehaviorPoseMath.blend(
            children: [(pose(0), 0), (pose(10), 1)],
            fallback: pose(-1)
        )
        #expect(abs(onlySecond.bones[0].translation.x - 10) < tolerance)

        let none = BehaviorPoseMath.blend(
            children: [(pose(0), 0), (pose(10), -1)],
            fallback: pose(-1)
        )
        #expect(abs(none.bones[0].translation.x + 1) < tolerance)
    }

    @Test func blendsRotationAlongTheShortestArc() {
        // Halfway from -10 to +10 degrees is 0, not 180: the long way round
        // would put the blend on the far side of the circle.
        let blended = BehaviorPoseMath.blend(
            BehaviorFixture.bonePose(translation: .zero, rotation: rotation(degrees: -10)),
            BehaviorFixture.bonePose(translation: .zero, rotation: rotation(degrees: 10)),
            weight: 0.5
        )
        #expect(abs(blended.rotation.vector.z) < 1e-4)
        #expect(abs(abs(blended.rotation.vector.w) - 1) < 1e-4)
    }

    @Test func degenerateRotationNormalizesToIdentity() {
        let normalized = BehaviorPoseMath
            .normalized(simd_quatf(ix: 0, iy: 0, iz: 0, r: 0))
        #expect(normalized.vector == SIMD4<Float>(0, 0, 0, 1))
    }

    @Test func clampsBlendWeightOutsideTheUnitRange() {
        let past = BehaviorPoseMath.blend(pose(0), pose(10), weight: 4)
        #expect(abs(past.bones[0].translation.x - 10) < tolerance)
        let before = BehaviorPoseMath.blend(pose(0), pose(10), weight: -4)
        #expect(abs(before.bones[0].translation.x) < tolerance)
    }

    @Test func rootMotionIsTheDeltaBetweenTwoSamples() {
        let motion = BehaviorPoseMath.rootMotion(
            from: BehaviorFixture.bonePose(
                translation: SIMD3(1, 0, 0), rotation: rotation(degrees: 10)
            ),
            to: BehaviorFixture.bonePose(
                translation: SIMD3(4, 0, 0), rotation: rotation(degrees: 40)
            )
        )
        #expect(abs(motion.translation.x - 3) < tolerance)
        // 40 - 10 = 30 degrees about z, so the quaternion's z lane is sin(15).
        #expect(abs(motion.rotation.vector.z - sin(15 * .pi / 180)) < 1e-4)
    }

    @Test func concatenatedRootMotionAddsTheSecondRunInTheFirstFrame() {
        let quarterTurn = BehaviorRootMotion(
            translation: SIMD3(1, 0, 0), rotation: rotation(degrees: 90)
        )
        let forward = BehaviorRootMotion(
            translation: SIMD3(1, 0, 0), rotation: BehaviorPoseMath.identityRotation
        )
        let joined = BehaviorPoseMath.concatenating(quarterTurn, forward)
        // The second run's +x becomes +y after the first run's quarter turn.
        #expect(abs(joined.translation.x - 1) < 1e-4)
        #expect(abs(joined.translation.y - 1) < 1e-4)
    }

    @Test func appliesSamplesOntoTheReferencePose() {
        let base = BehaviorFixture.skeleton().referencePose
        let applied = BehaviorPoseMath.applying(
            [
                HKABoneTransformSample(
                    boneIndex: 1,
                    pose: BehaviorFixture.bonePose(translation: SIMD3(7, 7, 7))
                ),
                // Out of range: dropped rather than trapped.
                HKABoneTransformSample(
                    boneIndex: 99,
                    pose: BehaviorFixture.bonePose(translation: SIMD3(9, 9, 9))
                )
            ],
            to: base
        )
        #expect(applied.count == base.count)
        #expect(applied[1].translation == SIMD3<Float>(7, 7, 7))
        #expect(applied[0] == base[0])
        #expect(applied[2] == base[2])
    }
}
