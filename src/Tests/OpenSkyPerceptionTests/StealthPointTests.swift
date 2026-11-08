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
        #expect(!pool.isExposed)
    }

    @Test func theRefillWaitsTenSecondsAfterTheLastPositiveValue() {
        var pool = StealthPointPool(settings: settings)
        pool.advance(highestValue: 10, overThreshold: false, by: 1, settings: settings)
        pool.advance(highestValue: -10, overThreshold: false, by: 9, settings: settings)
        #expect(pool.points == 70)
        pool.advance(highestValue: -10, overThreshold: false, by: 1, settings: settings)
        pool.advance(highestValue: -10, overThreshold: false, by: 1, settings: settings)
        // 5 per second, plus 0.2 per point below zero.
        #expect(pool.points == 77)
    }

    @Test func anEmptyPoolDetectsUntilItIsFullAgain() {
        var pool = StealthPointPool(settings: settings)
        pool.advance(highestValue: 20, overThreshold: false, by: 2, settings: settings)
        #expect(pool.isExposed)
        #expect(pool.detects(value: 1, isSneaking: true, wasDetected: false, settings: settings))
        #expect(!pool.detects(value: -5, isSneaking: true, wasDetected: false, settings: settings))

        pool.advance(highestValue: 0, overThreshold: false, by: 10, settings: settings)
        pool.advance(highestValue: 0, overThreshold: false, by: 19, settings: settings)
        #expect(pool.isExposed)
        pool.advance(highestValue: 0, overThreshold: false, by: 1, settings: settings)
        #expect(!pool.isExposed)
    }

    @Test func aValueOverTheThresholdDetectsAtOnce() {
        var pool = StealthPointPool(settings: settings)
        #expect(pool.detects(value: 25, isSneaking: false, wasDetected: false, settings: settings))
        #expect(!pool.detects(value: 25, isSneaking: true, wasDetected: false, settings: settings))
        pool.advance(highestValue: 80, overThreshold: true, by: 0.1, settings: settings)
        #expect(pool.points == 0)
        #expect(pool.isExposed)
    }
}
