// The agent clock: frozen time stands still, a step moves it by exactly one
// frame, and resuming or scaling never jumps.

import OpenSkyRendering
import RenderingTesting
import Testing

@MainActor
struct SteppedWallClockTests {
    private let source = ManualWallClock(now: 100)

    @Test func runningClockFollowsTheSource() {
        let clock = SteppedWallClock(source: source)
        source.advance(by: 0.5)
        #expect(clock.now == 100.5)
    }

    @Test func aFrozenClockOnlyMovesOnSteppedFrames() {
        let clock = SteppedWallClock(source: source)
        clock.freeze()
        source.advance(by: 3)
        clock.beginFrame()
        #expect(clock.now == 100)
        clock.requestSteps(2, seconds: 0.25)
        clock.beginFrame()
        #expect(clock.now == 100.25)
        #expect(clock.pendingSteps == 1)
        clock.beginFrame()
        clock.beginFrame()
        #expect(clock.now == 100.5)
        #expect(clock.pendingSteps == 0)
        #expect(clock.frame == 4)
    }

    @Test func resumingContinuesFromTheFrozenTime() {
        let clock = SteppedWallClock(source: source)
        clock.freeze()
        source.advance(by: 10)
        clock.resume()
        source.advance(by: 1)
        #expect(clock.now == 101)
    }

    @Test func scaleChangesTheRateWithoutAJump() {
        let clock = SteppedWallClock(source: source)
        source.advance(by: 1)
        clock.setScale(0.5)
        #expect(clock.now == 101)
        source.advance(by: 2)
        #expect(clock.now == 102)
    }

    @Test func aRunningClockIgnoresSteps() {
        let clock = SteppedWallClock(source: source)
        clock.requestSteps(3, seconds: 1)
        clock.beginFrame()
        #expect(clock.now == 100)
        #expect(clock.pendingSteps == 0)
    }
}
