/// How a forced weather change arrives.
nonisolated public enum WeatherTransition: Sendable {
    /// Snap instantly (no blend) — tests + the UI "apply now" path.
    case instant
    /// Cross-fade over the target weather's derived transition duration.
    case timed
    /// A timed fade that runs `transitionAcceleration` times faster.
    case accelerated
}
