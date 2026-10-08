// The engine's one seeded random stream. Each user keeps its own seeding rule,
// so a fixed seed gives the same values on every machine and every run.

/// SplitMix64 (Steele, Lea, Flood, OOPSLA 2014). `SystemRandomNumberGenerator` and
/// GameplayKit do not promise a platform-stable sequence, so seeded rolls use this.
nonisolated public struct SplitMix64: RandomNumberGenerator, Equatable, Sendable {
    /// The golden-ratio increment added before each mix.
    public static let increment: UInt64 = 0x9E37_79B9_7F4A_7C15

    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= Self.increment
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// Value in `0 ..< 1` from the top 24 bits, the precision of a `Float` mantissa.
    public mutating func unitFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    /// Unbiased draw in `0 ..< upperBound` by rejection sampling. Shadows the
    /// standard library's generic version, whose algorithm may change between releases.
    public mutating func next(upperBound: UInt64) -> UInt64 {
        guard upperBound > 1 else { return 0 }
        let limit = UInt64.max - (UInt64.max % upperBound)
        var value = next()
        while value >= limit {
            value = next()
        }
        return value % upperBound
    }
}
