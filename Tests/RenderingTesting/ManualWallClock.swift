// A `WallClock` a test moves by hand, so a frame clock advances by an exact
// step without waiting for real time.

import OpenSkyRendering
import QuartzCore

@MainActor
public final class ManualWallClock: WallClock {
    public var now: CFTimeInterval

    public init(now: CFTimeInterval = 0) {
        self.now = now
    }

    public func advance(by seconds: CFTimeInterval) {
        now += seconds
    }
}
