// A seeded generator, so a lockpicking session can be replayed in a test.

import OpenSkyFormatsCore

nonisolated public struct LockpickingRandom: RandomNumberGenerator, Equatable, Sendable {
    private var generator: SplitMix64

    public init(seed: UInt64) {
        generator = SplitMix64(seed: seed)
    }

    public mutating func next() -> UInt64 {
        generator.next()
    }

    public mutating func uniform(in range: ClosedRange<Float>) -> Float {
        Float.random(in: range, using: &self)
    }
}
