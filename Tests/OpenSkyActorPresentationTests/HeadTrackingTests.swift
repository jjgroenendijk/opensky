// Head tracking: the look angles, their limits, the turn speed and dead zone, glances,
// and the bones it turns.

@testable import OpenSkyActorPresentation
import OpenSkyEngineTesting
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsTesting
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
        let settings = HeadTrackingSettings.vanilla
        #expect(abs(side.yaw - .pi / 3) < 0.0001, "fTrackXY is 60 degrees")
        #expect(side.pitch == settings.pitchRange.upperBound)
        var narrow = settings
        narrow.trackXY = 10
        let limited = try #require(
            HeadTrackingCore.look(from: Self.eye, at: SIMD3(-100, 10, 400), settings: narrow)
        )
        #expect(abs(limited.yaw - 10 * .pi / 180) < 0.0001)
        #expect(HeadTrackingCore.look(from: Self.eye, at: SIMD3(0, -100, 120)) == nil)
    }

    @Test func theHeadEasesTowardItsGoal() {
        let goal = HeadLook(yaw: 1, pitch: -0.2)
        let step = HeadTrackingCore.approach(.forward, goal, step: 0.1)
        #expect(abs(step.yaw - 0.1) < 0.0001)
        #expect(abs(step.pitch + 0.1) < 0.0001)
        #expect(HeadTrackingCore.approach(goal, goal, step: 0.1) == goal)
    }

    @Test func theTurnSpeedRampsBetweenTheTwoAngles() {
        let settings = HeadTrackingSettings.vanilla
        func degreesPerSecond(_ remaining: Float) -> Float {
            settings.turnSpeed(remaining: remaining * .pi / 180) * 180 / .pi
        }
        #expect(abs(degreesPerSecond(3) - 60) < 0.01)
        #expect(abs(degreesPerSecond(7.5) - 130) < 0.01)
        #expect(abs(degreesPerSecond(40) - 200) < 0.01)
    }

    @Test func aHeadAtRestWaitsOutTheDeadZoneThenTurnsAllTheWay() {
        let settings = HeadTrackingSettings.vanilla
        let degree: Float = .pi / 180
        let near = HeadLook(yaw: 5 * degree, pitch: 0)
        let rest = HeadTrackingCore.turn(
            .forward, toward: near, isTurning: false, deltaTime: 0.1, settings: settings
        )
        #expect(rest.look == .forward && !rest.isTurning)
        let far = HeadLook(yaw: 20 * degree, pitch: 0)
        var state = (look: HeadLook.forward, isTurning: false)
        var frames = 0
        repeat {
            state = HeadTrackingCore.turn(
                state.look, toward: far, isTurning: state.isTurning, deltaTime: 1 / 60,
                settings: settings
            )
            frames += 1
        } while state.isTurning && frames < 600
        #expect(abs(state.look.yaw - far.yaw) <= HeadTrackingCore.arrivedAngle)
        #expect(frames > 1 && frames < 600)
    }

    @Test func glancesFollowTheirTimerAndStayInRange() {
        let quiet = HeadTrackingSettings.vanilla.idle
        #expect(HeadTrackingCore.glance(at: 2.5, seed: 9, timing: quiet) == .forward)
        let timing = HeadGlanceTiming(
            offsetMin: 5, offsetMax: 10, pickNewOffset: 2, resetPosition: 4,
            stayInOffsetMin: 1, stayInOffsetMax: 1
        )
        #expect(HeadTrackingCore.glance(at: 1, seed: 9, timing: timing) == .forward)
        #expect(HeadTrackingCore.glance(at: 3.5, seed: 9, timing: timing) == .forward)
        let glance = HeadTrackingCore.glance(at: 2.5, seed: 9, timing: timing)
        for angle in [glance.yaw, glance.pitch] {
            let degrees = abs(angle) * 180 / .pi
            #expect(degrees >= 5 - 0.001 && degrees <= 10 + 0.001)
        }
        #expect(HeadTrackingCore.glance(at: 2.5, seed: 9, timing: timing) == glance)
    }

    @Test func theSettingsComeFromTheGame() throws {
        let store = try GameSettingFixture.store([
            "fHeadTrackSpeedMax": .float(90), "fTrackDeadZoneXY": .float(2),
            "fAIHeadTrackDialogueOffsetRandomValue": .float(6),
            "fAIHeadTrackOffsetRandomValueMax": .float(4)
        ])
        let settings = HeadTrackingSettings.resolve(store: store)
        #expect(settings.speedMax == 90 && settings.deadZoneXY == 2)
        #expect(settings.dialogue.offsetMin == 6 && settings.dialogue.offsetMax == 6)
        #expect(settings.idle.offsetMin == 0 && settings.idle.offsetMax == 4)
        #expect(settings.speedMin == 60, "a missing setting keeps the vanilla value")
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

    @Test func rollTiltsAroundTheForwardAxis() {
        let bones = SkeletonBoneIndex(names: ["NPC Neck [Neck]", "NPC Head [Head]", "Eye"])
        func at(_ y: Float, _ z: Float) -> float4x4 {
            var matrix = matrix_identity_float4x4
            matrix.columns.3 = SIMD4(0, y, z, 1)
            return matrix
        }
        let pose = SkeletonPose(bones: bones, matrices: [at(0, 100), at(0, 110), at(10, 130)])
        let look = HeadLook(yaw: 0, pitch: 0).adding(LipHeadMotion(pitch: 0, roll: 0.3, yaw: 0))
        let turned = HeadTrackingCore.apply(look, to: pose, parents: [-1, 0, 1])
        let moved = turned.matrices[2].columns.3
        #expect(abs(moved.y - 10) < 0.001)
        #expect(abs(moved.x) > 1)
        let head = turned.matrices[1].columns.3
        #expect(abs(simd_distance(moved, head) - simd_length(SIMD2<Float>(10, 20))) < 0.001)
    }

    @Test func aSkeletonWithoutTheBonesIsUnchanged() {
        let pose = SkeletonPose(
            bones: SkeletonBoneIndex(names: ["Horse Head"]), matrices: [matrix_identity_float4x4]
        )
        let turned = HeadTrackingCore.apply(HeadLook(yaw: 1, pitch: 0), to: pose, parents: [-1])
        #expect(turned.matrices == pose.matrices)
    }
}
