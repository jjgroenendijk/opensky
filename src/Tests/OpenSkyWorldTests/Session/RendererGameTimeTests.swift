// The real time a session's frames ran, for `Utility.GetCurrentRealTime`.

@testable import OpenSkyWorld
import OpenSkyWorldInterface
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
}
