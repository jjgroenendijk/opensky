// What the crime coordinator asks the app to do. See docs/engine/coordinators.md.

/// One change to the world outside the crime domain.
nonisolated public enum CrimeCommand: Equatable, Sendable {
    /// A HUD notice, such as a bounty added or cleared.
    case showNotice(String)
    /// The guards' hostility from the player's bounties, for the faction derivation.
    case applyGuardHostility(GuardCrimeHostility)
    /// A crime stat on the journal's Stats page, such as "Times Jailed".
    case incrementStat(String, by: Int32)
    /// Raises a stat to `value` when it is lower, such as "Largest Bounty".
    case raiseStat(String, to: Int32)
}
