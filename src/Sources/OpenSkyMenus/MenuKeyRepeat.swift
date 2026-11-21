// A held menu direction repeats on the game's timing, whichever device holds it.
// See docs/engine/as2-input.md#keys-the-game-sends.

public import OpenSkyMenusInterface

nonisolated public struct MenuKeyRepeat: Sendable {
    /// Seconds before the first repeat, then between repeats.
    public struct Timing: Equatable, Sendable {
        public let delay: Double
        public let interval: Double

        public static let standard = Timing(delay: 0.5, interval: 0.1)
        /// The journal, which holds the System page too, repeats faster.
        public static let journal = Timing(delay: 0.2, interval: 0.075)
    }

    private var held: MenuInputEvent.Direction?
    private var nextRepeat: Double?

    public init() {}

    /// Follows the presses and releases the menus are sent.
    public mutating func note(_ event: MenuInputEvent) {
        switch event {
        case let .move(direction):
            held = direction
            nextRepeat = nil
        case let .release(direction) where direction == held:
            held = nil
            nextRepeat = nil
        default:
            break
        }
    }

    /// The direction to send again now, if one is due. The first call after a press
    /// starts the delay, so the press itself is never sent twice.
    public mutating func due(now: Double, timing: Timing) -> MenuInputEvent.Direction? {
        guard let held else { return nil }
        guard let next = nextRepeat else {
            nextRepeat = now + timing.delay
            return nil
        }
        guard now >= next else { return nil }
        nextRepeat = now + timing.interval
        return held
    }

    /// Forgets the held direction, as when the last menu closes.
    public mutating func reset() {
        held = nil
        nextRepeat = nil
    }
}
