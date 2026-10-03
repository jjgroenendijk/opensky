// A wall clock an agent can freeze, step by exact frames, and scale. Every
// frame clock reads the renderer's `WallClock`, so freezing this one freezes
// the whole simulation while the window keeps drawing (docs/tools/agent-control.md).

import QuartzCore

public final class SteppedWallClock: WallClock {
    private let source: any WallClock
    /// Simulated time at `anchor`.
    private var base: CFTimeInterval
    /// Source time when `base` was last set.
    private var anchor: CFTimeInterval
    private var stepSeconds: CFTimeInterval = 1.0 / 60

    public private(set) var isFrozen = false
    public private(set) var scale: Double = 1
    /// Steps asked for and not yet drawn.
    public private(set) var pendingSteps = 0
    /// Live frames drawn since this clock was made.
    public private(set) var frame = 0

    public init(source: any WallClock = MediaWallClock()) {
        self.source = source
        base = source.now
        anchor = base
    }

    public var now: CFTimeInterval {
        isFrozen ? base : base + (source.now - anchor) * scale
    }

    public func freeze() {
        guard !isFrozen else { return }
        rebase()
        isFrozen = true
    }

    /// Runs on from the frozen time, so resuming never jumps.
    public func resume() {
        guard isFrozen else { return }
        anchor = source.now
        isFrozen = false
        pendingSteps = 0
    }

    public func setScale(_ scale: Double) {
        rebase()
        self.scale = scale
    }

    /// Queues frames of `seconds` each. A running clock ignores it.
    public func requestSteps(_ count: Int, seconds: CFTimeInterval) {
        guard isFrozen else { return }
        stepSeconds = seconds
        pendingSteps += max(count, 0)
    }

    public func beginFrame() {
        frame += 1
        guard isFrozen, pendingSteps > 0 else { return }
        base += stepSeconds
        pendingSteps -= 1
    }

    private func rebase() {
        base = now
        anchor = source.now
    }
}
