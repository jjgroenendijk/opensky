// A controller rumble a sound asks for: its descriptor's rumble send times the level the
// listener hears (docs/engine/sound-mix.md#rumble).

nonisolated public struct SoundRumble: Equatable, Sendable {
    /// A looping sound has no end, so its rumble stops after this many seconds.
    public static let maximumSeconds: Float = 1

    public var small: Float
    public var big: Float
    public var seconds: Float

    public init(small: Float, big: Float, seconds: Float) {
        self.small = min(max(small, 0), 1)
        self.big = min(max(big, 0), 1)
        self.seconds = max(seconds, 0)
    }
}
