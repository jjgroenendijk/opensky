// The watchdog that ends a launched tour whose frames stopped.

@testable import OpenSkyWorld
import Testing

struct BenchmarkWatchdogTests {
    private static let step = BenchmarkWatchdog.checkIntervalSeconds

    @Test func aTourThatNeverStartsEndsAfterTheStartLimit() {
        var watchdog = BenchmarkWatchdog(now: 0)
        var now = 0.0
        var reason: String?
        while reason == nil, now < 2 * BenchmarkWatchdog.startLimitSeconds {
            now += Self.step
            reason = watchdog.check(frameCount: 0, now: now)
        }
        #expect(reason == "the tour did not start in 600 s")
        #expect(now > BenchmarkWatchdog.startLimitSeconds)
    }

    @Test func framesKeepTheTourAliveAndAStallEndsIt() {
        var watchdog = BenchmarkWatchdog(now: 0)
        var now = 0.0
        for frames in 1 ... 100 {
            now += Self.step
            #expect(watchdog.check(frameCount: frames, now: now) == nil)
        }
        let stalledAt = now
        var reason: String?
        while reason == nil {
            now += Self.step
            reason = watchdog.check(frameCount: 100, now: now)
        }
        #expect(reason == "the GPU drew no frame for 240 s")
        #expect(now - stalledAt > BenchmarkWatchdog.stallLimitSeconds)
    }

    @Test func aLateCheckRestartsTheStallClock() {
        var watchdog = BenchmarkWatchdog(now: 0)
        #expect(watchdog.check(frameCount: 1, now: Self.step) == nil)
        let busyUntil = Self.step + BenchmarkWatchdog.stallLimitSeconds + 60
        #expect(watchdog.check(frameCount: 1, now: busyUntil) == nil)
        #expect(watchdog.check(frameCount: 1, now: busyUntil + Self.step) == nil)
    }
}
