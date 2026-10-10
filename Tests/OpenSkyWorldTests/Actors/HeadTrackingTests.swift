// Head tracking: the look angles, their limits, the easing, and the bones it turns.

import OpenSkyFormatsCore
@testable import OpenSkyWorld
import simd
import Testing

@MainActor
struct HeadTrackingTests {
    private static let eye = SIMD3<Float>(0, 0, 120)

    @Test func aTargetAheadAndToTheLeftTurnsTheHeadLeft() throws {
        let look = try #require(HeadTrackingCore.look(from: Self.eye, at: SIMD3(-100, 100, 120)))
        #expect(abs(look.yaw - .pi / 4) < 0.001)
        #expect(abs(look.pitch) < 0.001)
    }

    @Test func turnsAreLimitedAndATargetBehindIsIgnored() throws {
        let side = try #require(HeadTrackingCore.look(from: Self.eye, at: SIMD3(-100, 10, 400)))
        #expect(side.yaw == HeadTrackingCore.maximumYaw)
        #expect(side.pitch == HeadTrackingCore.maximumPitch)
        #expect(HeadTrackingCore.look(from: Self.eye, at: SIMD3(0, -100, 120)) == nil)
    }

    @Test func theHeadEasesTowardItsGoal() {
        let goal = HeadLook(yaw: 1, pitch: -0.2)
        let step = HeadTrackingCore.approach(.forward, goal, step: 0.1)
        #expect(abs(step.yaw - 0.1) < 0.0001)
        #expect(abs(step.pitch + 0.1) < 0.0001)
        #expect(HeadTrackingCore.approach(goal, goal, step: 0.1) == goal)
    }

    @Test func theNeckAndHeadTurnAndTheBodyStays() {
        let bones = SkeletonBoneIndex(names: ["Root", "NPC Neck [Neck]", "NPC Head [Head]", "Eye"])
        func at(_ z: Float) -> float4x4 {
            var matrix = matrix_identity_float4x4
            matrix.columns.3 = SIMD4(0, 0, z, 1)
            return matrix
        }
        var eye = matrix_identity_float4x4
        eye.columns.3 = SIMD4(0, 10, 130, 1)
        let pose = SkeletonPose(bones: bones, matrices: [at(0), at(100), at(110), eye])
        let turned = HeadTrackingCore.apply(
            HeadLook(yaw: .pi / 2, pitch: 0), to: pose, parents: [-1, 0, 1, 2]
        )
        #expect(turned.matrices[0] == pose.matrices[0])
        // The eye sat 10 units ahead of the head; a quarter turn left moves it to -X.
        let moved = turned.matrices[3].columns.3
        #expect(abs(moved.x + 10) < 0.001)
        #expect(abs(moved.y) < 0.001)
        #expect(abs(moved.z - 130) < 0.001)
    }

    @Test func aSkeletonWithoutTheBonesIsUnchanged() {
        let pose = SkeletonPose(
            bones: SkeletonBoneIndex(names: ["Horse Head"]), matrices: [matrix_identity_float4x4]
        )
        let turned = HeadTrackingCore.apply(HeadLook(yaw: 1, pitch: 0), to: pose, parents: [-1])
        #expect(turned.matrices == pose.matrices)
    }
}
