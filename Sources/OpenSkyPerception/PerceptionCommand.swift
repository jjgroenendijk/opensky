// What the perception coordinator asks the app to do. See docs/engine/coordinators.md.

import OpenSkyFormatsESM

/// One change to the world outside the perception domain.
nonisolated public enum PerceptionCommand: Equatable, Sendable {
    /// Credits Sneak skill uses to an actor that stayed hidden.
    case reportSneakSkillUse(Float, by: ReferenceKey)
}
