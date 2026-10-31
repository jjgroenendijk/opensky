// What the crime coordinator asks the app to do. See docs/engine/coordinators.md.

import OpenSkyFormatsESM

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
    /// A witness of a trespass speaks its warning (`TRES`).
    case speakTrespassWarning(by: ReferenceKey)
    /// The player stole this much from a faction: Papyrus `GetStolenItemValueCrime`
    /// counts the witnessed thefts and `GetStolenItemValueNoCrime` the others.
    case stoleFromFaction(ReferenceKey, value: Int64, witnessed: Bool)
    /// A guard settled the pickpocket catches charged to this crime faction. A forgotten
    /// catch also ends the victim's two-day refusal.
    case settlePickpocketCatches(ReferenceKey, forgotten: Bool)
}
