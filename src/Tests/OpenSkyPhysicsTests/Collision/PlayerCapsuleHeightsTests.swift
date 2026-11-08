// The heights a spell aims at and light is read at, and the ball probe.

@testable import OpenSkyPhysics
import Testing

struct PlayerCapsuleHeightsTests {
    @Test
    func theStandardCapsuleHasItsCentreAndTorso() {
        #expect(PlayerCapsule.standard.centreHeight == 64)
        #expect(PlayerCapsule.standard.torsoHeight == 56)
    }

    @Test
    func aBallIsAsTallAsItIsWide() {
        let ball = PlayerCapsule.ball(radius: 10)
        #expect(ball.height == 20 && ball.eyeHeight == 10 && ball.radius == 10)
    }
}
