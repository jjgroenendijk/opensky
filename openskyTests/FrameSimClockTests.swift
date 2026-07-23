// Pausable frame delta clock (todo 8.1.2): the first tick is zero, deltas clamp
// to maxDelta, a paused tick returns zero while keeping its mark fresh, and
// resuming after any pause length yields one frame of delta rather than the
// whole paused span (the no-time-jump proof). Synthetic times, no wall clock.

@testable import opensky
import Testing

struct FrameSimClockTests {
    @Test
    func firstTickReturnsZero() {
        var clock = FrameSimClock()
        #expect(clock.advance(to: 100, paused: false) == 0)
    }

    @Test
    func measuresDeltaBetweenTicks() {
        var clock = FrameSimClock()
        _ = clock.advance(to: 100, paused: false)
        #expect(abs(clock.advance(to: 100.05, paused: false) - 0.05) < 1e-4)
    }

    @Test
    func clampsLargeDeltaToMax() {
        var clock = FrameSimClock(maxDelta: 0.1)
        _ = clock.advance(to: 100, paused: false)
        // A five-second gap (breakpoint / app nap) clamps to the 0.1 cap.
        #expect(clock.advance(to: 105, paused: false) == 0.1)
    }

    @Test
    func pausedTickReturnsZero() {
        var clock = FrameSimClock()
        _ = clock.advance(to: 100, paused: false)
        #expect(clock.advance(to: 100.05, paused: true) == 0)
    }

    @Test
    func resumeAfterLongPauseHasNoTimeJump() {
        var clock = FrameSimClock(maxDelta: 0.1)
        _ = clock.advance(to: 100, paused: false)
        // Ten seconds of real time pass while paused across many frames.
        for frame in 1 ... 600 {
            let now = 100 + Double(frame) / 60
            #expect(clock.advance(to: now, paused: true) == 0)
        }
        // First unpaused frame after resume: only one frame of delta, never the
        // ten-second paused span.
        let resumeNow = 100 + Double(601) / 60
        let resumeDelta = clock.advance(to: resumeNow, paused: false)
        #expect(abs(resumeDelta - Float(1.0 / 60)) < 1e-4)
    }

    @Test
    func resetDropsReferenceMark() {
        var clock = FrameSimClock()
        _ = clock.advance(to: 100, paused: false)
        clock.reset()
        #expect(clock.advance(to: 100.05, paused: false) == 0)
    }
}
