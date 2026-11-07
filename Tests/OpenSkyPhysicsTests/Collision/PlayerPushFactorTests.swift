// The game's scale on the player's push, by body mass and collision layer.

@testable import OpenSkyPhysics
import Testing

struct PlayerPushFactorTests {
    @Test func heavyMasslessAndProjectileBodiesAreNotPushed() {
        #expect(PlayerPushFactor.factor(mass: 95, layer: 4, impulse: 1) == 0)
        #expect(PlayerPushFactor.factor(mass: 0, layer: 4, impulse: 1) == 0)
        #expect(PlayerPushFactor.factor(mass: 5, layer: 6, impulse: 1) == 0)
    }

    @Test func eachLayerTakesItsFactor() {
        #expect(PlayerPushFactor.factor(mass: 5, layer: 4, impulse: 1) == 2)
        #expect(PlayerPushFactor.factor(mass: 5, layer: 10, impulse: 1) == 3)
        #expect(PlayerPushFactor.factor(mass: 50, layer: 10, impulse: 1) == 0.1)
        #expect(PlayerPushFactor.factor(mass: 5, layer: 14, impulse: 1) == 0.1)
    }

    @Test func aVeryFastPushShrinks() {
        let mass: Float = 1
        let tooFast = 2000 * mass * 69.99125
        let factor = PlayerPushFactor.factor(mass: mass, layer: 4, impulse: tooFast)
        #expect(abs(factor - 1) < 0.001)
    }
}
