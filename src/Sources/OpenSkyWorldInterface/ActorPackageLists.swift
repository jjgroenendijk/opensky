import OpenSkyFormatsESM
import simd

/// A code-driven behaviour that suspends the actor's usual package choice. A
/// valid package from the matching override list runs in its place.
nonisolated public enum PackageSituation: String, CaseIterable, Sendable {
    /// The actor sees a fight it does not join.
    case spectator
    case observeDeadBody
    /// A guard package warns a trespasser.
    case guardWarn
    case combat
}
