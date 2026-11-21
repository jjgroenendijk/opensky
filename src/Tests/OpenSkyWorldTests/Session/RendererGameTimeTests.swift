// The real time a session's frames ran, for `Utility.GetCurrentRealTime`.

@testable import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

struct RendererGameTimeTests {
    @Test func framesAddTheirRealTime() {
        var time = RendererGameTime()
        for frame in 0 ... 60 {
            time.advanceRealTime(to: 100 + Double(frame) / 60)
        }
        #expect(abs(time.realSecondsRun - 1) < 1e-4)
    }

    @Test func aStallCountsOneCappedFrame() {
        var time = RendererGameTime()
        time.advanceRealTime(to: 10)
        time.advanceRealTime(to: 15)
        #expect(abs(time.realSecondsRun - 0.1) < 1e-6)
    }

    @Test func aMoveAcrossMidnightPassesOneDayHoweverFarItJumps() {
        var time = RendererGameTime()
        time.clock = GameClock(hour: 23)
        time.passTime(wallDelta: 1, timescale: 20)
        #expect(time.pendingDaysPassed == 0)
        time.passTime(wallDelta: 300, timescale: 20)
        #expect(time.consumeDaysPassed() == 1)
        #expect(time.pendingDaysPassed == 0)

        var travel = time.clock
        travel.setDaysPassed(time.clock.daysPassed + 3)
        time.skipTime(to: travel)
        #expect(time.consumeDaysPassed() == 1)
        #expect(time.weatherGameSecondsMark == nil)
    }
}
