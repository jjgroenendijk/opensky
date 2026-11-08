// Movement values that locomotion, perception, and the movement readouts share.

/// One tuning value and the name of where it came from: a GMST, a MOVT record,
/// or an OpenSky fallback.
nonisolated public struct MovementSetting: Equatable, Sendable {
    public let value: Float
    public let source: String

    public init(value: Float, source: String) {
        self.value = value
        self.source = source
    }
}

/// Which gait the bridge resolved for a step. Sneak outranks sprint, which
/// outranks run: crouching cancels a sprint in vanilla rather than stacking
/// with it, and swimming replaces all three.
nonisolated public enum LocomotionGait: String, Equatable, Sendable {
    case walk
    case run
    case sprint
    case sneak
    case swim
}
