// The actor the camera comes close to fades out over half a second and back in when the
// camera leaves; the player fades at once.

@testable import OpenSkyRenderCore
import simd
import Testing

struct ActorCameraFadeTests {
    private static func actor(_ formID: UInt32, x: Float, player: Bool = false) -> ActorCameraFade
        .Candidate
    {
        ActorCameraFade.Candidate(
            formID: formID, feet: SIMD3(x, 0, 0), height: 128, radius: 20, isPlayer: player
        )
    }

    @Test func picksTheNearestActorWithinReachOfTheEye() {
        let eye = SIMD3<Float>(0, 0, 100)
        let actors = [Self.actor(1, x: 45), Self.actor(2, x: 30), Self.actor(3, x: 60)]
        #expect(ActorCameraFade.choose(eye: eye, among: actors)?.formID == 2)
        #expect(ActorCameraFade.choose(eye: eye, among: [Self.actor(3, x: 60)]) == nil)
        // Above the head the distance counts from the top of the axis.
        #expect(ActorCameraFade.choose(eye: SIMD3(0, 0, 300), among: [Self.actor(1, x: 0)]) == nil)
    }

    @Test func chosenActorFadesOutOverHalfASecondAndBackIn() {
        var fade = ActorCameraFade()
        let near = [Self.actor(7, x: 10)]
        fade.advance(eye: SIMD3(0, 0, 50), candidates: near, seconds: 0.25)
        #expect(abs((fade.fadeOuts[7] ?? 0) - 0.5) < 1e-5)
        fade.advance(eye: SIMD3(0, 0, 50), candidates: near, seconds: 1)
        #expect(fade.fadeOuts[7] == 1)
        fade.advance(eye: SIMD3(500, 0, 50), candidates: near, seconds: 0.25)
        #expect(abs((fade.fadeOuts[7] ?? 0) - 0.5) < 1e-5)
        fade.advance(eye: SIMD3(500, 0, 50), candidates: near, seconds: 0.25)
        #expect(fade.fadeOuts[7] == nil)
    }

    @Test func playerFadesAtOnce() {
        var fade = ActorCameraFade()
        fade.advance(
            eye: SIMD3(0, 0, 50),
            candidates: [Self.actor(0x14, x: 5, player: true)],
            seconds: 1.0 / 60
        )
        #expect(fade.fadeOuts[0x14] == 1)
    }
}
