/// Measures how long a step takes, for logs, stats, and benchmark reports. It is the one
/// clock a game-rule module may read, and its reading never feeds game state
/// (`docs/decisions/deterministic-rules.md`).
nonisolated public struct Stopwatch: Sendable {
    private let started = ContinuousClock.now

    public init() {}

    public var elapsed: Duration {
        ContinuousClock.now - started
    }

    public var milliseconds: Double {
        let parts = elapsed.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }
}
