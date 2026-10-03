// A seeded generator, so a lockpicking session can be replayed in a test.

/// SplitMix64 (Steele, Lea, Flood 2014). Small and good enough for a sweet spot.
nonisolated public struct LockpickingRandom: RandomNumberGenerator, Equatable, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    public mutating func uniform(in range: ClosedRange<Float>) -> Float {
        Float.random(in: range, using: &self)
    }
}
