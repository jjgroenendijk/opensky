// The time source the frame clocks read. The renderer holds one, so a test can
// step time with a manual clock instead of waiting.

import QuartzCore

/// Current wall time in seconds, on a monotonic scale with an arbitrary origin.
public protocol WallClock: AnyObject {
    var now: CFTimeInterval { get }
    /// Called once at the start of each live frame, before any clock reads.
    func beginFrame()
}

extension WallClock {
    public func beginFrame() {}
}

/// The live clock: `CACurrentMediaTime()`, the same host time Core Animation uses.
public final class MediaWallClock: WallClock {
    public init() {}

    public var now: CFTimeInterval {
        CACurrentMediaTime()
    }
}
