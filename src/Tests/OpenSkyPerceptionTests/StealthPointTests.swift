// The stealth point pool (CK wiki "Stealth Points"): a positive detection drains
// it three times as fast, the refill waits 10 seconds, and an empty pool detects.

@testable import OpenSkyPerceptionInterface
import Testing

struct StealthPointTests {
    private let settings = StealthPointSettings.vanilla

    @Test func aPositiveValueDrainsAtThreeTimesItsValue() {
        var pool = StealthPointPool(settings: settings)
        pool.advance(highestValue: 10, overThreshold: false, by: 1, settings: settings)
        #expect(pool.points == 70)
    }

    @Test func theRefillWaitsTenSecondsAfterTheLastPositiveValue() {
        var pool = StealthPointPool(settings: settings)
        pool.advance(highestValue: 10, overThreshold: false, by: 1, settings: settings)
        pool.advance(highestValue: -10, overThreshold: false, by: 9, settings: settings)
        #expect(pool.points == 70)
        pool.advance(highestValue: -10, overThreshold: false, by: 1, settings: settings)
        pool.advance(highestValue: -10, overThreshold: false, by: 1, settings: settings)
        // 5 per second: 0.2 per point below zero is less here.
        #expect(pool.points == 75)
        pool.advance(highestValue: -50, overThreshold: false, by: 1, settings: settings)
        #expect(pool.points == 85)
    }

    @Test func aValueOverTheThresholdEmptiesThePool() {
        var pool = StealthPointPool(settings: settings)
        pool.advance(highestValue: 80, overThreshold: true, by: 0.1, settings: settings)
        #expect(pool.points == 0)
    }

    @Test func aNoticedTargetDoesNotRefill() {
        var pool = StealthPointPool(settings: settings)
        pool.advance(highestValue: 10, overThreshold: false, by: 1, settings: settings)
        pool.advance(
            highestValue: -10, overThreshold: false, by: 60, settings: settings, mayRefill: false
        )
        #expect(pool.points == 70)
    }

    @Test func aHitAndAnEventCapThePoints() {
        var pool = StealthPointPool(settings: settings)
        pool.cap(at: CombatTargetTrack.eventPointCap)
        #expect(pool.points == 75)
        pool.cap(at: CombatTargetTrack.hitPointCap)
        #expect(pool.points == 50)
        pool.cap(at: CombatTargetTrack.eventPointCap)
        #expect(pool.points == 50)
    }
}
