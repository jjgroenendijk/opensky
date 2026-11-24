// The actor the camera's sweep touches near the eye fades out, its drawn alpha following
// at 1 per second; the player fades when the eye is inside its capsule, never below 0.1.

@testable import OpenSkyRenderCore
import simd
import Testing

struct ActorCameraFadeTests {
    private static let frame: Float = 1.0 / 60
    private static let pivot = SIMD3<Float>(0, 0, 120)

    /// An upright capsule of radius 18 and height 128 standing at `x`, `y`.
    private static func actor(_ formID: UInt32, x: Float, y: Float = 0)
        -> ActorCameraFade.Candidate
    {
        ActorCameraFade.Candidate(formID: formID, bodies: [
            ActorCameraFade.Body(
                start: SIMD3(x, y, 18), end: SIMD3(x, y, 110), radius: 18, boundRadius: 64
            )
        ])
    }

    private static let player = ActorCameraFade.Target(
        formID: 0x14, feet: .zero, radius: 18, height: 128, seatedHead: nil
    )

    private static func scene(
        eye: SIMD3<Float>, actors: [ActorCameraFade.Candidate],
        camera: ActorCameraFade.Camera = .startsFades, target: ActorCameraFade.Target? = player
    ) -> ActorCameraFade.Scene {
        ActorCameraFade.Scene(
            camera: camera,
            eye: eye,
            pivot: pivot,
            actors: actors,
            target: target
        )
    }

    private static func run(
        _ fade: inout ActorCameraFade, _ scene: ActorCameraFade.Scene?, seconds: Float
    ) {
        for _ in 0 ..< Int((seconds / frame).rounded()) {
            fade.advance(scene: scene, seconds: frame)
        }
    }

    @Test func aNeighbourBesideTheSweepStaysSolid() {
        // Riders on one bench: the orbit behind the player passes 40 units from each.
        let riders = [Self.actor(2, x: 60), Self.actor(3, x: -65)]
        let eye = SIMD3<Float>(0, -180, 130)
        #expect(ActorCameraFade
            .choose(eye: eye, pivot: Self.pivot, actors: riders, target: nil) == nil)
    }

    @Test func anEyeNearABodyPicksThatBody() {
        let npc = Self.actor(5, x: 0, y: -80)
        let eye = SIMD3<Float>(0, -70, 100)
        #expect(ActorCameraFade
            .choose(eye: eye, pivot: Self.pivot, actors: [npc], target: nil) == 5)
        // The sweep passes the NPC far from the eye: it stays solid.
        let far = SIMD3<Float>(0, -400, 100)
        #expect(ActorCameraFade
            .choose(eye: far, pivot: Self.pivot, actors: [npc], target: nil) == nil)
    }

    @Test func theLastActorAlongTheSweepWins() {
        let eye = SIMD3<Float>(0, -140, 100)
        let actors = [Self.actor(7, x: 0, y: -130), Self.actor(6, x: 0, y: -50)]
        #expect(ActorCameraFade
            .choose(eye: eye, pivot: Self.pivot, actors: actors, target: nil) == 7)
    }

    @Test func aSweepFromInsideABodyTouchesItAtTheStart() {
        let body = ActorCameraFade.Body(start: SIMD3(0, 0, 0), end: SIMD3(0, 0, 100), radius: 10)
        let hit = ActorCameraFade.sweep(
            from: SIMD3(0, 0, 50),
            to: SIMD3(0, -200, 50),
            against: body
        )
        #expect(hit?.along == 0)
        let side = ActorCameraFade.sweep(
            from: SIMD3(-100, 0, 50),
            to: SIMD3(100, 0, 50),
            against: body
        )
        // The sphere of 15 touches the capsule of 10 at x = -25.
        #expect(side.map { abs($0.along - 0.375) < 1e-3 } == true)
        #expect(side.map { abs($0.contact.x + 10) < 1e-2 } == true)
    }

    @Test func anActorFadesOutAndBackInAtTheDrawnRate() {
        var fade = ActorCameraFade()
        let near = [Self.actor(7, x: 0, y: -80)]
        let inside = Self.scene(eye: SIMD3(0, -70, 100), actors: near)
        Self.run(&fade, inside, seconds: 0.5)
        // The amount is 0 after 0.5 s; the drawn alpha has moved 0.5.
        #expect(abs((fade.fadeOuts[7] ?? 0) - 0.5) < 0.02)
        Self.run(&fade, inside, seconds: 0.6)
        #expect(fade.fadeOuts[7] == 1)
        let away = Self.scene(eye: SIMD3(0, 200, 150), actors: near)
        Self.run(&fade, away, seconds: 0.5)
        #expect(fade.chosen == nil)
        #expect(abs((fade.fadeOuts[7] ?? 0) - 0.5) < 0.02)
        Self.run(&fade, away, seconds: 0.6)
        #expect(fade.fadeOuts[7] == nil)
    }

    @Test func theDrawnAlphaMovesAtMostATenthInAFrame() {
        var fade = ActorCameraFade()
        let inside = Self.scene(eye: SIMD3(0, -70, 100), actors: [Self.actor(7, x: 0, y: -80)])
        fade.advance(scene: inside, seconds: 1)
        #expect(abs((fade.fadeOuts[7] ?? 0) - 0.1) < 1e-5)
    }

    @Test func thePlayerFadesToATenthWhenTheEyeIsInsideIt() {
        var fade = ActorCameraFade()
        let inside = Self.scene(eye: SIMD3(30, 0, 100), actors: [])
        Self.run(&fade, inside, seconds: 2)
        #expect(fade.chosen == 0x14)
        #expect(abs((fade.fadeOuts[0x14] ?? 0) - 0.9) < 1e-4)
        #expect(ActorCameraFade.choose(
            eye: SIMD3(60, 0, 100), pivot: Self.pivot, actors: [], target: Self.player
        ) == nil)
    }

    @Test func aTallerPlayerFadesSoonerFromAbove() {
        let tall = ActorCameraFade.Target(
            formID: 0x14, feet: .zero, radius: 18, height: 184, seatedHead: nil
        )
        // 30 units out from the axis and 30 above the head, lowered by 184 - 124 = 60.
        let eye = SIMD3<Float>(0, 30, 214)
        #expect(ActorCameraFade.isInside(eye: eye, target: tall))
        #expect(!ActorCameraFade.isInside(eye: eye, target: Self.player))
    }

    @Test func aSeatedPlayerFadesNearItsHead() {
        let seated = ActorCameraFade.Target(
            formID: 0x14, feet: .zero, radius: 18, height: 128, seatedHead: SIMD3(0, 0, 90)
        )
        #expect(ActorCameraFade.isInside(eye: SIMD3(0, -40, 90), target: seated))
        #expect(!ActorCameraFade.isInside(eye: SIMD3(0, -50, 90), target: seated))
    }

    @Test func firstPersonStartsNoFadeAndLetsTheHeldActorGo() {
        var fade = ActorCameraFade()
        let near = [Self.actor(7, x: 0, y: -80)]
        Self.run(&fade, Self.scene(eye: SIMD3(0, -70, 100), actors: near), seconds: 1.1)
        #expect(fade.fadeOuts[7] == 1)
        let firstPerson = Self.scene(eye: SIMD3(0, -70, 100), actors: near, camera: .holdsFades)
        fade.advance(scene: firstPerson, seconds: Self.frame)
        #expect(fade.chosen == nil)
        Self.run(&fade, firstPerson, seconds: 1.1)
        #expect(fade.fadeOuts[7] == nil)
    }

    @Test func aFrozenCameraChoosesNothing() {
        var fade = ActorCameraFade()
        let near = [Self.actor(7, x: 0, y: -80)]
        let frozen = Self.scene(eye: SIMD3(0, -70, 100), actors: near, camera: .frozen)
        Self.run(&fade, frozen, seconds: 0.5)
        #expect(fade.chosen == nil)
        #expect(fade.fadeOuts.isEmpty)
    }

    @Test func anActorStillFadingInWaitsBeforeItFadesAgain() {
        var fade = ActorCameraFade()
        let near = [Self.actor(7, x: 0, y: -80)]
        let inside = Self.scene(eye: SIMD3(0, -70, 100), actors: near)
        Self.run(&fade, inside, seconds: 1.1)
        Self.run(&fade, Self.scene(eye: SIMD3(0, 200, 150), actors: near), seconds: 0.25)
        // Back inside while its amount is still rising: not held this frame.
        fade.advance(scene: inside, seconds: Self.frame)
        #expect(fade.chosen == nil)
        Self.run(&fade, inside, seconds: 0.4)
        #expect(fade.chosen == 7)
    }
}
