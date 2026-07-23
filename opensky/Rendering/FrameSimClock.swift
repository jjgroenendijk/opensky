// Wall-clock frame delta with a pause gate (todo 8.1.2). The renderer advances
// world simulation (game time, animations, weather, particles) by the real time
// elapsed since the previous frame; menu mode freezes that advance without a
// time jump when it resumes. See docs/engine/menu-mode.md.

import QuartzCore

/// Per-frame delta-time source. `advance` returns the seconds elapsed since the
/// previous tick, clamped to `maxDelta` so a long stall never dumps a huge step
/// into the simulation. While paused it returns zero yet still moves its
/// reference mark to the current time, so resuming after any pause length yields
/// a single frame of delta, never the whole paused span. Value type: each timed
/// subsystem owns its own clock.
struct FrameSimClock {
    /// Hard cap on a single delta, in seconds. A breakpoint, the first frame
    /// after resume, or an app-nap wake must not advance the sim by the whole
    /// elapsed gap.
    var maxDelta: Float

    private var lastTick: CFTimeInterval?

    init(maxDelta: Float = 0.1) {
        self.maxDelta = maxDelta
    }

    /// Records `now` as the newest tick and returns the delta to feed the sim.
    /// The first tick (no prior mark) and any paused tick return zero, but both
    /// still advance the mark so the next unpaused tick measures one frame.
    mutating func advance(to now: CFTimeInterval, paused: Bool) -> Float {
        defer { lastTick = now }
        guard let lastTick, !paused else { return 0 }
        return Float(min(now - lastTick, TimeInterval(maxDelta)))
    }

    /// Forgets the reference mark so the next `advance` returns zero. Used when a
    /// scene swap or camera reseed should not carry a stale delta forward.
    mutating func reset() {
        lastTick = nil
    }
}
