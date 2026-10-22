// The 3D lock's pose: which sequence plays when, and the pick turned by its angle.

import OpenSkyFormatsMesh
import OpenSkyInventoryInterface
@testable import OpenSkyMenus
import OpenSkyRendering
import simd
import Testing

struct LockpickingLockPoseTests {
    static func sequence(_ name: String, seconds: Float) -> NIFSequence {
        NIFSequence(
            name: name,
            timing: ControllerTiming(
                cycle: .clamp, frequency: 1, phase: 0, startTime: 0, stopTime: seconds
            ),
            textKeys: [],
            tracks: []
        )
    }

    static let intro = sequence("Intro", seconds: 1)
    static let turn = sequence("Rotate", seconds: 3)
    static let strain = sequence("PickDamage", seconds: 0.5)
    static let broken = sequence("PickBreak", seconds: 1.7)

    static func pose(
        seconds: Float, rotation: Float = 0, straining: Bool = false, broken: Float? = nil
    ) -> LockpickingLockPose {
        LockpickingLockPose(
            pickSeconds: seconds, lockSeconds: seconds, pickAngle: 0, lockRotation: rotation,
            isStraining: straining, brokenSeconds: broken
        )
    }

    @Test func theLockPlaysItsIntroThenHoldsRotateAtTheTurn() {
        let early = Self.pose(seconds: 0.4).lockPlaying(
            intro: Self.intro, turn: Self.turn, turnSeconds: 1.5
        )
        #expect(early.map(\.sequence.name) == ["Intro"])
        #expect(early.first?.seconds == 0.4)
        let turning = Self.pose(seconds: 5, rotation: 0.5).lockPlaying(
            intro: Self.intro, turn: Self.turn, turnSeconds: 1.5
        )
        #expect(turning.map(\.sequence.name) == ["Rotate"])
        #expect(turning.first?.seconds == 0.75)
        let open = Self.pose(seconds: 5, rotation: 2).lockPlaying(
            intro: Self.intro, turn: Self.turn, turnSeconds: 1.5
        )
        #expect(open.first?.seconds == 1.5)
    }

    @Test func thePickJigglesWhileStrainingAndFliesOffWhenBroken() {
        let resting = Self.pose(seconds: 2).pickPlaying(
            intro: Self.intro, strain: Self.strain, broken: Self.broken
        )
        #expect(resting.map(\.sequence.name) == ["Intro"])
        let straining = Self.pose(seconds: 2.2, straining: true).pickPlaying(
            intro: Self.intro, strain: Self.strain, broken: Self.broken
        )
        #expect(straining.map(\.sequence.name) == ["Intro", "PickDamage"])
        let snapped = Self.pose(seconds: 2, broken: 3).pickPlaying(
            intro: Self.intro, strain: Self.strain, broken: Self.broken
        )
        #expect(snapped.map(\.sequence.name) == ["PickBreak"])
        #expect(snapped.first?.seconds == LockpickingLockPose.breakSeconds)
    }

    @Test func thePickTurnsWithTheCylinder() {
        var pose = Self.pose(seconds: 3, rotation: 0.5)
        pose.pickAngle = -10
        #expect(pose.pickTurnDegrees == 35)
        pose.lockRotation = 3
        #expect(pose.pickTurnDegrees == 80)
    }

    @Test func thePickTurnsAboutTheViewAxisThroughItsOwnOrigin() {
        var local = matrix_identity_float4x4
        local.columns.3 = SIMD4(10, -16, 7, 1)
        #expect(LockpickingLockPose.turnedPick(local, angleDegrees: 0) == local)
        let turned = LockpickingLockPose.turnedPick(local, angleDegrees: 90)
        let origin = turned.columns.3
        #expect(simd_distance(SIMD3(origin.x, origin.y, origin.z), SIMD3(10, -16, 7)) < 1e-4)
        // A point above the pivot ends on the screen's right (+X, the camera's right).
        let tip = turned * SIMD4(0, 0, 1, 1)
        #expect(abs(tip.x - 11) < 1e-4 && abs(tip.z - 7) < 1e-4)
    }
}

struct LockpickingOverlayTests {
    static func frame(drawsLockModel: Bool) -> LockpickingMenuPresentation {
        LockpickingMenuPresentation(
            title: "Door", difficulty: .adept, pickAngle: 0, halfArc: 90, lockRotation: 0.5,
            pickHealth: 1, picksRemaining: 3, isStraining: false, drawsLockModel: drawsLockModel
        )
    }

    @Test func besideThe3DLockTheOverlayKeepsOnlyBarsAndText() {
        let flat = Self.frame(drawsLockModel: false).scene.nodes
        let beside = Self.frame(drawsLockModel: true).scene.nodes
        #expect(beside.count < flat.count)
        #expect(beside.allSatisfy { node in
            if case .panel = node.content {
                return false
            }
            return node.anchor == .bottom
        })
    }
}
