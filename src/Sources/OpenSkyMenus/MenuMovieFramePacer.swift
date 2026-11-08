// Steps a menu movie at its own frame rate from the render loop's clock. CLIK
// runs a row press and a page change on later movie frames, not in the key event.

import Foundation

nonisolated public struct MenuMovieFramePacer: Equatable, Sendable {
    /// A long stall runs a few frames, not seconds of animation in one go.
    static let maximumTicks = 4
    static let fallbackFrameRate = 30.0

    private var last: Double?
    private var owed = 0.0

    public init() {}

    /// Movie frames due at `now` seconds. The first call only starts the clock.
    public mutating func ticks(at now: Double, frameRate: Double) -> Int {
        defer { last = now }
        guard let last, now > last else { return 0 }
        let rate = frameRate > 0 ? frameRate : Self.fallbackFrameRate
        owed = min(owed + (now - last) * rate, Double(Self.maximumTicks))
        let due = Int(owed)
        owed -= Double(due)
        return due
    }
}
