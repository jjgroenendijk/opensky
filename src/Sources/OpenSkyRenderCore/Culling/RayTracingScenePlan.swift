// Which scene geometry the ray-traced shadows test against, and when the acceleration
// structures change. See docs/rendering/ray-traced-shadows.md.

/// What the plan needs to know about one draw group.
nonisolated public struct RayTracingCaster: Equatable, Sendable {
    public var castsShadows = true
    public var isSkinned = false
    public var isMorphed = false
    public var isAlphaTested = false
    /// A physics body moves it, so its pose changes every frame.
    public var isMoved = false

    public init() {}
}

/// What the frame does with the acceleration structures.
nonisolated public enum RayTracingAction: Equatable, Sendable {
    case none
    /// Builds every structure again: the scene changed, or the effect turned on.
    case build
    /// Frees the structures: the effect turned off.
    case release
}

nonisolated public enum RayTracingScenePlan {
    /// Only rigid, opaque geometry that casts shadows goes in. Actors, moved bodies, and
    /// alpha-tested foliage keep their shadow-map shadows, which the shader still applies.
    public static func includes(_ caster: RayTracingCaster) -> Bool {
        caster.castsShadows && !caster.isSkinned && !caster.isMorphed
            && !caster.isAlphaTested && !caster.isMoved
    }

    public static func action(active: Bool, built: Bool, current: Bool) -> RayTracingAction {
        if !active {
            return built ? .release : .none
        }
        return built && current ? .none : .build
    }
}
