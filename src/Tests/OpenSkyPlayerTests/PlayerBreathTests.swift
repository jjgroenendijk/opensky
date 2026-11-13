// The breath timer under water: 10 + 50 x 0.2 = 20 seconds of breath, then health lost each
// second.

@testable import OpenSkyPlayer
import Testing

struct PlayerBreathTests {
    @Test func aLongDiveCostsHealthAfterTheBreathRunsOut() {
        var breath = PlayerBreath()
        let first = breath.advance(
            seconds: 16,
            submerged: true,
            waterBreathing: false,
            maximumHealth: 100
        )
        #expect(first == 0)
        #expect(breath.remainingSeconds == 4)
        // Four seconds of breath left, then six seconds of 8% of 100 health a second.
        let second = breath.advance(
            seconds: 10,
            submerged: true,
            waterBreathing: false,
            maximumHealth: 100
        )
        #expect(abs(second - 48) < 1e-4)
        #expect(breath.remainingSeconds == 0)
        #expect(PlayerLocomotionReadout.breathLine(breath).contains("drowning"))
    }

    @Test func waterBreathingAndSurfacingKeepTheBreathFull() {
        var breath = PlayerBreath()
        #expect(breath.advance(
            seconds: 60,
            submerged: true,
            waterBreathing: true,
            maximumHealth: 100
        ) == 0)
        #expect(breath.remainingSeconds == 20)
        _ = breath.advance(seconds: 18, submerged: true, waterBreathing: false, maximumHealth: 100)
        _ = breath.advance(
            seconds: 0.1,
            submerged: false,
            waterBreathing: false,
            maximumHealth: 100
        )
        #expect(breath.remainingSeconds == 20)
        #expect(PlayerLocomotionReadout.breathLine(breath).contains("above water"))
    }

    @Test func theMultiplierAddsFiftyTimesItsValue() {
        var settings = BreathSettings()
        settings.baseSeconds = 5
        settings.multiplier = 1
        #expect(settings.breathSeconds == 55)
    }

    @Test func theEyesDecideWhetherThePlayerIsUnderWater() {
        #expect(PlayerBreath.isSubmerged(eyeZ: 90, waterSurface: 100))
        #expect(!PlayerBreath.isSubmerged(eyeZ: 110, waterSurface: 100))
        #expect(!PlayerBreath.isSubmerged(eyeZ: 0, waterSurface: nil))
    }
}
