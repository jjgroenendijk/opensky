/// Where a ridden dragon is in its breath attack.
nonisolated public enum DragonBreathPhase: Equatable, Sendable {
    case ready
    case inhaling(seconds: Float)
    case exhaling(seconds: Float)
}
