import OpenSkyFormatsESM

/// What zero health does to one actor.
nonisolated public enum ZeroHealthOutcome: Equatable, Sendable {
    case dies
    /// `StartDeferredKill` holds the death until `EndDeferredKill`.
    case deferred
    case bleedsOut
}
