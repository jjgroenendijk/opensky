// Mirrored clips, reference frame travel, the pose matching rules, and the offset
// animation's time mapping, each against hand-worked values.

import Foundation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import simd
import Testing

struct BehaviorClipFeatureTests {
    /// A root with a left bone and a right bone, all in the reference rotation.
    private static let skeleton = BehaviorSkeleton(
        referencePose: [
            BehaviorFixture.bonePose(translation: SIMD3(0, 0, 0)),
            BehaviorFixture.bonePose(translation: SIMD3(-1, 0, 0)),
            BehaviorFixture.bonePose(translation: SIMD3(1, 0, 0))
        ],
        parentIndices: [-1, 0, 0]
    )

    private static let mirror = BehaviorMirror(
        HKBMirroredSkeletonInfo(
            mirrorAxis: SIMD4(1, 0, 0, 0), bonePairMap: [0, 2, 1], unresolved: []
        ),
        skeleton: skeleton
    )

    private static func close(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Bool {
        simd_length(lhs - rhs) < 1e-5
    }

    private static func close(_ lhs: simd_quatf, _ rhs: simd_quatf) -> Bool {
        abs(abs(simd_dot(lhs.vector, rhs.vector)) - 1) < 1e-5
    }

    /// The left bone's sample lands on the right bone, with x reflected.
    @Test func aSampleMovesToItsPartnerReflected() throws {
        let turn = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        let sample = HKABoneTransformSample(
            boneIndex: 1,
            pose: BehaviorFixture.bonePose(translation: SIMD3(3, 4, 5), rotation: turn)
        )
        let mirrored = try #require(Self.mirror.mirroring([sample], isAdditive: false).first)
        #expect(mirrored.boneIndex == 2)
        #expect(Self.close(mirrored.pose.translation, SIMD3(-3, 4, 5)))
        // A turn about z reflected through the x plane turns the other way.
        #expect(Self.close(mirrored.pose.rotation, turn.inverse))
    }

    @Test func rootTravelIsReflected() {
        let motion = BehaviorRootMotion(
            translation: SIMD3(1, 2, 0),
            rotation: simd_quatf(angle: 0.3, axis: SIMD3(0, 0, 1)),
            isExtracted: true
        )
        let mirrored = Self.mirror.mirroring(motion)
        #expect(Self.close(mirrored.translation, SIMD3(-1, 2, 0)))
        #expect(Self.close(mirrored.rotation, simd_quatf(angle: -0.3, axis: SIMD3(0, 0, 1))))
        #expect(mirrored.isExtracted)
    }

    @Test func aNearlyAxisAlignedRotationSnaps() {
        #expect(BehaviorMirror.axisAligned.count == 24)
        let near = simd_normalize(simd_quatf(ix: 0.05, iy: 0, iz: 0, r: 1))
        #expect(BehaviorMirror.snapped(near) == simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
    }

    // MARK: - Reference frame

    private static let frame = HKADefaultAnimatedReferenceFrame(
        up: SIMD4(0, 0, 1, 0),
        forward: SIMD4(0, 1, 0, 0),
        duration: 2,
        samples: [SIMD4(0, 0, 0, 0), SIMD4(1, 0, 0, 0), SIMD4(2, 0, 0, 0.5)],
        unresolved: []
    )

    @Test func theFrameIsLinearBetweenSamples() throws {
        let pose = try #require(Self.frame.pose(at: 1.5))
        #expect(Self.close(pose.translation, SIMD3(1.5, 0, 0)))
        #expect(Self.close(pose.rotation, simd_quatf(angle: 0.25, axis: SIMD3(0, 0, 1))))
    }

    /// A wrap travels to the end and on from the start: 0.5 + 0.5.
    @Test func aWrapAddsTheRunToTheEndAndFromTheStart() {
        let straight = Self.frame.motion(from: 0.25, to: 0.75, wrapped: false, window: 0 ... 2)
        #expect(Self.close(straight.translation, SIMD3(0.5, 0, 0)))
        #expect(straight.isExtracted)
        let wrapped = Self.frame.motion(from: 1.5, to: 0.5, wrapped: true, window: 0 ... 2)
        // The run to the end turns by the heading change, 0.25 rad, before the second run.
        #expect(abs(wrapped.translation.x - (0.5 + 0.5 * cos(0.25))) < 1e-4)
    }

    // MARK: - Pose matching

    @Test func errorsRankTheClosestSignatureFirst() {
        let live = simd_quatf(angle: 0.1, axis: SIMD3(1, 0, 0))
        let errors = BehaviorPoseMatchRules.errors(
            live: live,
            signatures: [simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)), live, nil]
        )
        #expect(errors[1] < 1e-6)
        #expect(errors[0] > 0.9)
        #expect(errors[2] == 1)
    }

    @Test func theSwitchTimeMovesFromNoErrorToFullError() {
        #expect(BehaviorPoseMatchRules.switchTime(error: 0, noError: 0.2, fullError: 1) == 0.2)
        let half = BehaviorPoseMatchRules.switchTime(error: 0.5, noError: 0.2, fullError: 1)
        #expect(abs(half - 0.6) < 1e-6)
    }

    @Test func weightsStepTowardTheCurrentChild() {
        let weights = BehaviorPoseMatchRules.stepped([1, 0.5, 0.05], toward: 1, by: 0.25)
        #expect(weights == [0.75, 0.75, 0])
    }

    /// Lying on the back and on the front give opposite frames, at any heading.
    @Test func theFrameIgnoresHeadingButNotWhichSideIsUp() throws {
        let back = try #require(BehaviorPoseMatchRules.frame(
            root: SIMD3(0, 0, 0), other: SIMD3(1, 0, 0), another: SIMD3(0, 1, 0)
        ))
        let turned = try #require(BehaviorPoseMatchRules.frame(
            root: SIMD3(0, 0, 0), other: SIMD3(0, 1, 0), another: SIMD3(-1, 0, 0)
        ))
        let front = try #require(BehaviorPoseMatchRules.frame(
            root: SIMD3(0, 0, 0), other: SIMD3(1, 0, 0), another: SIMD3(0, -1, 0)
        ))
        #expect(Self.close(back, turned))
        #expect(BehaviorPoseMatchRules.errors(live: back, signatures: [front])[0] > 0.9)
    }

    // MARK: - Offset animation and playback speed

    @Test func theOffsetFractionClampsAndAnEmptyRangeIsZero() {
        #expect(BehaviorGraphInstance.offsetFraction(5, start: 0, end: 10) == 0.5)
        #expect(BehaviorGraphInstance.offsetFraction(20, start: 0, end: 10) == 1)
        #expect(BehaviorGraphInstance.offsetFraction(3, start: 2, end: 2) == 0)
    }

    /// Five frames: the phase runs from the second frame (0.25) to the end.
    @Test func theOffsetPhaseStartsOneFrameIn() {
        #expect(BehaviorGraphInstance.offsetPhase(0, frameCount: 5) == 0.25)
        #expect(BehaviorGraphInstance.offsetPhase(1, frameCount: 5) == 1)
        #expect(BehaviorGraphInstance.offsetPhase(0.5, frameCount: 1) == 0.5)
    }

    @Test func aSpeedNearZeroRunsAtTheSmallestSpeed() {
        #expect(BehaviorGraphInstance.playbackSpeed(0.0001) == 0.001)
        #expect(BehaviorGraphInstance.playbackSpeed(0) == -0.001)
        #expect(BehaviorGraphInstance.playbackSpeed(-0.0005) == -0.001)
        #expect(BehaviorGraphInstance.playbackSpeed(2) == 2)
    }
}
