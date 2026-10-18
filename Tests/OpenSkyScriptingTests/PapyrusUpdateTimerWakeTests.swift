// The registry skips its scan until the earliest timer is due. These tests pin
// that each timer still fires on the step the full scan would pick.

@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
@testable import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusUpdateTimerWakeTests {
    private static let step = 1.0 / 30

    private static func key(_ objectID: UInt32) -> PapyrusInstanceKey {
        PapyrusInstanceKey(
            reference: .plugin(name: "Test.esp", objectID: objectID),
            scriptName: "S"
        )
    }

    /// The first tick after registration where the scan's due test holds.
    private static func expectedTick(duration: Double) -> Int {
        var ticks = 0
        while Double(ticks) * step < duration {
            ticks += 1
        }
        return ticks
    }

    private static func fireTicks(
        _ registry: inout PapyrusUpdateTimerRegistry, steps: Int, clock: GameClock? = nil
    ) -> [Int: [PapyrusUpdateTimerRegistry.Firing]] {
        var fired: [Int: [PapyrusUpdateTimerRegistry.Firing]] = [:]
        for tick in 1 ... steps {
            let firings = registry.advanceStep(stepSeconds: step, gameClock: clock)
            if !firings.isEmpty {
                fired[tick] = firings
            }
        }
        return fired
    }

    @Test(arguments: [0.0, 0.01, 0.1, 0.2, 1.0 / 3, 0.5, 1, 2.5])
    func singleShotFiresOnTheScanStep(duration: Double) {
        var registry = PapyrusUpdateTimerRegistry()
        registry.register(key: Self.key(1), slot: .realSingleShot, interval: duration)
        let fired = Self.fireTicks(&registry, steps: 120)
        #expect(Array(fired.keys) == [max(1, Self.expectedTick(duration: duration))])
    }

    @Test func replacingASlotWithAShorterIntervalFiresAtTheShorterOne() {
        var registry = PapyrusUpdateTimerRegistry()
        registry.register(key: Self.key(1), slot: .realSingleShot, interval: 3)
        _ = registry.advanceStep(stepSeconds: Self.step, gameClock: nil)
        registry.register(key: Self.key(1), slot: .realSingleShot, interval: 0.1)
        let fired = Self.fireTicks(&registry, steps: 120)
        #expect(Array(fired.keys) == [Self.expectedTick(duration: 0.1)])
    }

    @Test func aRemovedEarlyTimerLeavesTheLaterOneOnTime() {
        var registry = PapyrusUpdateTimerRegistry()
        registry.register(key: Self.key(1), slot: .realSingleShot, interval: 0.1)
        registry.register(key: Self.key(2), slot: .realSingleShot, interval: 1)
        registry.removeAll(for: Self.key(1))
        let fired = Self.fireTicks(&registry, steps: 120)
        #expect(Array(fired.keys) == [Self.expectedTick(duration: 1)])
        #expect(fired.values.first?.map(\.key) == [Self.key(2)])
    }

    @Test func repeatingTimersFireInRegistrationOrderEachInterval() {
        var registry = PapyrusUpdateTimerRegistry()
        registry.register(key: Self.key(2), slot: .realRepeating, interval: 0.5)
        registry.register(key: Self.key(1), slot: .realRepeating, interval: 0.5)
        let first = Self.expectedTick(duration: 0.5)
        let fired = Self.fireTicks(&registry, steps: first * 3)
        #expect(fired.keys.sorted() == [first, first * 2, first * 3])
        #expect(fired[first]?.map(\.key) == [Self.key(2), Self.key(1)])
    }

    @Test func gameTimeTimerWaitsForItsOwnClock() {
        var registry = PapyrusUpdateTimerRegistry()
        _ = registry.advanceStep(stepSeconds: Self.step, gameClock: GameClock(hour: 10))
        registry.register(key: Self.key(1), slot: .gameTimeSingleShot, interval: 1)
        registry.register(key: Self.key(2), slot: .realSingleShot, interval: 0.1)
        let realFired = Self.fireTicks(&registry, steps: 30, clock: GameClock(hour: 10))
        #expect(realFired.values.flatMap { $0.map(\.key) } == [Self.key(2)])
        let later = registry.advanceStep(stepSeconds: Self.step, gameClock: GameClock(hour: 11))
        #expect(later.map(\.key) == [Self.key(1)])
    }
}
