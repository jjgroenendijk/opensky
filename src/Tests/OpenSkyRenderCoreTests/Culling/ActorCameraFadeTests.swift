// The actor the camera's probe runs into fades out over half a second and back in when
// the camera leaves; the player fades at once when the eye touches its capsule.

@testable import OpenSkyFormatsCore
@testable import OpenSkyRenderCore
import simd
import Testing

struct ActorCameraFadeTests {
    /// A body 40 wide and 128 tall standing at `x`, `y`.
    private static func actor(_ formID: UInt32, x: Float, y: Float = 0, player: Bool = false)
        -> ActorCameraFade.Candidate
    {
        ActorCameraFade.Candidate(
            formID: formID,
            shapes: [ModelBounds(min: SIMD3(x - 20, y - 20, 0), max: SIMD3(x + 20, y + 20, 128))],
            isPlayer: player
        )
    }

    @Test func aNeighbourBesideAFirstPersonEyeStaysSolid() {
        // Riders on one cart bench: the eye is 40 units from the next rider's body.
        let eye = SIMD3<Float>(0, 0, 100)
        let riders = [Self.actor(2, x: 40), Self.actor(3, x: -45)]
        #expect(ActorCameraFade.choose(eye: eye, pivot: nil, among: riders) == nil)
        // A third-person orbit behind the player does not pass through them either.
        let pivot = SIMD3<Float>(0, 0, 112)
        let behind = SIMD3<Float>(0, -180, 130)
        #expect(ActorCameraFade.choose(eye: behind, pivot: pivot, among: riders) == nil)
    }

    @Test func anEyePushedIntoABodyPicksThatBody() {
        let pivot = SIMD3<Float>(0, 0, 112)
        // A wall holds the eye 10 units inside the NPC that stands behind the player.
        let eye = SIMD3<Float>(0, -70, 100)
        let npc = Self.actor(5, x: 0, y: -80)
        #expect(ActorCameraFade.choose(eye: eye, pivot: pivot, among: [npc])?.formID == 5)
        // The probe passes the NPC far from the eye: it stays solid.
        let far = SIMD3<Float>(0, -400, 100)
        #expect(ActorCameraFade.choose(eye: far, pivot: pivot, among: [npc]) == nil)
    }

    @Test func theLastBodyAlongTheProbeWins() {
        let pivot = SIMD3<Float>(0, 0, 100)
        let eye = SIMD3<Float>(0, -120, 100)
        let near = Self.actor(6, x: 0, y: -50)
        let atEye = Self.actor(7, x: 0, y: -115)
        #expect(ActorCameraFade.choose(eye: eye, pivot: pivot, among: [atEye, near])?.formID == 7)
    }

    @Test func chosenActorFadesOutOverHalfASecondAndBackIn() {
        var fade = ActorCameraFade()
        let pivot = SIMD3<Float>(0, 0, 112)
        let near = [Self.actor(7, x: 0, y: -80)]
        let inside = SIMD3<Float>(0, -70, 100)
        fade.advance(eye: inside, pivot: pivot, candidates: near, seconds: 0.25)
        #expect(abs((fade.fadeOuts[7] ?? 0) - 0.5) < 1e-5)
        fade.advance(eye: inside, pivot: pivot, candidates: near, seconds: 1)
        #expect(fade.fadeOuts[7] == 1)
        fade.advance(eye: SIMD3(500, 0, 50), pivot: pivot, candidates: near, seconds: 0.25)
        #expect(abs((fade.fadeOuts[7] ?? 0) - 0.5) < 1e-5)
        fade.advance(eye: SIMD3(500, 0, 50), pivot: pivot, candidates: near, seconds: 0.25)
        #expect(fade.fadeOuts[7] == nil)
    }

    @Test func playerFadesAtOnceWhenTheEyeTouchesItsCapsule() {
        var fade = ActorCameraFade()
        let pivot = SIMD3<Float>(0, 0, 112)
        let player = [Self.actor(0x14, x: 0, player: true)]
        fade.advance(eye: SIMD3(30, 0, 100), pivot: pivot, candidates: player, seconds: 1.0 / 60)
        #expect(fade.fadeOuts[0x14] == 1)
        #expect(ActorCameraFade.choose(eye: SIMD3(60, 0, 100), pivot: pivot, among: player) == nil)
    }

    @Test func firstPersonStartsNoFadeAndRestoresAFadedActor() {
        var fade = ActorCameraFade()
        let pivot = SIMD3<Float>(0, 0, 112)
        let near = [Self.actor(7, x: 0, y: -80), Self.actor(0x14, x: 0, player: true)]
        fade.advance(eye: SIMD3(0, -70, 100), pivot: pivot, candidates: near, seconds: 1)
        #expect(fade.fadeOuts[7] == 1)
        // The view switches to first person with the eye in the same place.
        fade.advance(eye: SIMD3(0, -70, 100), pivot: nil, candidates: near, seconds: 0.25)
        #expect(fade.chosen == nil)
        #expect(abs((fade.fadeOuts[7] ?? 0) - 0.5) < 1e-5)
    }

    @Test func aTallerPlayerFadesSoonerFromAbove() {
        let pivot = SIMD3<Float>(0, 0, 160)
        let tall = ActorCameraFade.Candidate(
            formID: 0x14,
            shapes: [ModelBounds(min: SIMD3(-20, -20, 0), max: SIMD3(20, 20, 184))],
            isPlayer: true
        )
        // 30 units out from the axis and 30 above the head, lowered by 184 - 124 = 60.
        let eye = SIMD3<Float>(0, 30, 214)
        #expect(ActorCameraFade.choose(eye: eye, pivot: pivot, among: [tall])?.formID == 0x14)
        #expect(ActorCameraFade.touchesPlayer(SIMD3(0, 30, 214), Self.actor(0x14, x: 0)) == false)
    }

    @Test func aProbeOfNoLengthHitsNothing() {
        let box = ModelBounds(min: SIMD3(-10, -10, 0), max: SIMD3(10, 10, 10))
        #expect(ActorCameraFade.entry(from: .zero, to: .zero, into: box) == nil)
        let entry = ActorCameraFade.entry(from: SIMD3(-100, 0, 5), to: SIMD3(100, 0, 5), into: box)
        #expect(entry.map { abs($0 - 0.375) < 1e-5 } == true)
    }
}
