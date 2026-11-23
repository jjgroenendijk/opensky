@testable import OpenSkyPlayer
import simd
import Testing

struct DialogueTurnTests {
    private static let eye = SIMD3<Float>(0, 0, 120)

    /// A speaker behind and to the left is reached the short way, by a left turn.
    @Test func turnsTheShortWayRound() {
        let turn = DialogueTurn(eye: Self.eye, yaw: 0, pitch: 0, aim: SIMD3(-100, 10, 120))
        #expect(abs(turn.targetYaw - atan2f(10, -100)) < 1e-5)
        let back = DialogueTurn(eye: Self.eye, yaw: 3, pitch: 0, aim: SIMD3(-100, -10, 120))
        #expect(back.targetYaw > .pi)
        #expect(back.targetYaw - back.startYaw < .pi)
    }

    /// Level with the aim point, the view settles 0.17 radians below it.
    @Test func aimsBelowTheLookAtPoint() {
        let turn = DialogueTurn(eye: Self.eye, yaw: 0, pitch: 0, aim: SIMD3(100, 0, 120))
        #expect(abs(turn.targetPitch + DialogueTurn.pitchOffset) < 1e-5)
    }

    /// Half the time has passed and the view is sin(pi / 4) of the way there; at the
    /// end it stands on the target and the turn is done.
    @Test func easesOutOverOneSecond() {
        var turn = DialogueTurn(eye: Self.eye, yaw: 0, pitch: 0, aim: SIMD3(0, 100, 120))
        let half = turn.advance(by: 0.5)
        #expect(abs(half.yaw - .pi / 2 * sinf(.pi / 4)) < 1e-5)
        #expect(!turn.isDone)
        let end = turn.advance(by: 0.6)
        #expect(abs(end.yaw - .pi / 2) < 1e-5)
        #expect(turn.isDone)
    }

    /// The speaker's head settles into its pose after the first frame; the turn follows.
    @Test func followsAMovedAim() {
        var turn = DialogueTurn(eye: Self.eye, yaw: 0, pitch: 0, aim: SIMD3(0, 100, 120))
        turn.retarget(eye: Self.eye, aim: SIMD3(100, 0, 120))
        #expect(abs(turn.targetYaw) < 1e-5)
        #expect(abs(turn.targetPitch + DialogueTurn.pitchOffset) < 1e-5)
    }

    /// Looking away is untouched inside the soft stop, damped between the stops, and
    /// stopped past the hard stop. Turning back is never limited.
    @Test(arguments: zip([Float(10), 30, 50], [Float(1), 0.198, 0]))
    func dampensLookingAway(degrees: Float, scale: Float) {
        let offset = DialogueTurn.speakerOffset(
            yaw: -degrees * .pi / 180, eye: Self.eye, aim: SIMD3(100, 0, 120)
        )
        let away = DialogueTurn.lookScale(lookRight: 1, offset: offset, stops: .firstPerson)
        #expect(abs(away - scale) < 1e-4)
        let back = DialogueTurn.lookScale(lookRight: -1, offset: offset, stops: .firstPerson)
        #expect(back == 1)
    }
}
