/// A seeded stream of draws that a closure seam captures, so a coordinator's default roll
/// repeats from run to run. Each coordinator owns its own stream; no stream is shared.
nonisolated public final class RandomStream {
    private var generator: SplitMix64

    public init(seed: UInt64) {
        generator = SplitMix64(seed: seed)
    }

    public func float(in range: Range<Float>) -> Float {
        Float.random(in: range, using: &generator)
    }

    public func float(in range: ClosedRange<Float>) -> Float {
        Float.random(in: range, using: &generator)
    }

    /// A draw in `0 ..< count`; zero when `count` is not positive.
    public func int(below count: Int) -> Int {
        count > 0 ? Int.random(in: 0 ..< count, using: &generator) : 0
    }
}
