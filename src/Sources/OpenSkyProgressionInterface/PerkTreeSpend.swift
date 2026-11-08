import Foundation
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData

/// Why a perk-point spend was refused. Exhaustive, because the perk tree shows each case as
/// the reason a node is unavailable. A missing perk is an answer, not a crash.
nonisolated public enum PerkSpendRefusal: Error, Equatable, Sendable {
    /// This load order carries no PERK record for the requested key.
    case unresolvedPerk
    /// The record's `DATA` playable flag is clear.
    case notPlayable
    /// The actor already owns it.
    case alreadyOwned
    /// No perk tree in this load order grants it, so no point can buy it.
    case notInPerkTree
    /// The chain rank below this one is unowned; carries the record to take
    /// first.
    case previousRankMissing(ReferenceKey)
    /// The box asks for a parent and none of the boxes reaching it is owned.
    case parentMissing
    /// The record's own condition run did not hold — a skill requirement, or a
    /// prerequisite the record states as `HasPerk`.
    case unmetCondition
}
