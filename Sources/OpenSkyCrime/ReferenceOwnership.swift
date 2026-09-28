// Ownership resolution (issue #504, roadmap item 21.5): the one query that
// answers "does this actor own, or may it freely use, that reference?"
//
// Ownership was decoded long before anything read it. `PlacedReference` carries
// `XOWN`/`XRNK`, `Container` carries the COED per-entry owner, and item 12.1's
// `ReferenceOwnershipReadout` says outright that it is "an inspection, not a
// gate". This file is the gate. Nothing here decides that a crime happened —
// that is `CrimeRuntime` — it decides only whether taking a thing would be one.
//
// ## Precedence
//
// A reference's own `XOWN` wins; a reference without one inherits the owner of
// the cell it stands in. UESP states the inheritance from the player's side:
// "an item's name that appears in red text means that the item is owned and
// picking it up is stealing" (<https://en.uesp.net/wiki/Skyrim:Crime>), and
// every crate in Belethor's shop reads as owned while carrying no `XOWN` of its
// own — the shop's `CELL` carries it (observed on this install:
// `WhiterunBelethorsGeneralGoods` has one `XOWN` field and Breezehome, the
// house the player buys, has none).
//
// So the order is reference, then cell, then unowned. It is a *first match*
// rather than a merge: a chest inside an owned shop that names its own owner is
// that owner's, and the shop's claim does not also apply.
//
// ## What an owner may be
//
// `XOWN` names either an NPC_ or a FACT, exactly as it does on a REFR, and
// nothing in the field says which. The resolution is therefore by lookup: a
// link the load order carries a FACT for is a faction owner, and anything else
// is an actor owner. That ordering matters — asking the faction store first is
// the only way to tell the two apart without decoding the target record.
//
// A faction owner carries the rank a member needs before the property is
// theirs to use, from `XRNK`. An absent `XRNK` reads as rank 0, the lowest rank
// vanilla authors, so an ordinary member of the owning faction may use it.
//
// Documented in docs/engine/crime.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// Resolves `XOWN` links against the load order and answers the ownership
/// question over them.
///
/// A value snapshot rather than a live handle, the shape every other
/// record-reading seam in this engine takes: it holds the FACT store and the
/// plugin the links are spelled against, and answers are pure functions of the
/// arguments.
nonisolated public struct OwnershipResolver: Sendable {
    /// Rank an owning faction demands when the record authors no `XRNK`.
    ///
    /// Zero, the lowest rank vanilla authors — `ActorFactionMembership.rank` is
    /// signed precisely so a negative rank can mean "a member the rank titles
    /// do not name", and an ordinary rank-0 member of the owning faction is
    /// exactly who a shop's back room is meant to be open to.
    public static let defaultRequiredRank: Int32 = 0

    /// Load-order FACT lookup, which is what distinguishes a faction owner from
    /// an actor owner.
    public let factions: FactionStore
    /// The plugin `XOWN` links are relative to.
    public let pluginName: String

    /// The owner one `XOWN`/`XRNK` pair names.
    ///
    /// A link the load order carries a FACT for is a faction owner; anything
    /// else is an actor owner, including a link nothing resolves — a dangling
    /// owner is still a claim, and reading it as "unowned" would quietly make
    /// a shop free to loot when a plugin went missing. A link whose *plugin* is
    /// not loaded resolves to nothing at all and is the one case that reports
    /// nil.
    public func owner(of ownership: RecordOwnership) -> ReferenceOwner? {
        guard let resolved = factions.resolvedID(ownership.owner, fromPlugin: pluginName) else {
            return nil
        }
        let key = ReferenceKey(resolved: resolved)
        guard factions.faction(key: key) != nil else { return .actor(key) }
        return .faction(key, requiredRank: ownership.requiredRank ?? Self.defaultRequiredRank)
    }

    /// The owner in force for a reference, applying the reference-then-cell
    /// precedence.
    public func owner(reference: RecordOwnership?, cell: RecordOwnership?) -> ReferenceOwner? {
        if let reference, let owner = owner(of: reference) {
            return owner
        }
        guard let cell else { return nil }
        return owner(of: cell)
    }

    /// What `actor` may do with a reference owned by `owner`.
    public func verdict(for actor: CrimeActor, owner: ReferenceOwner?) -> OwnershipVerdict {
        actor.verdict(on: owner)
    }

    /// The whole question in one call: the two `XOWN` pairs in, a verdict out.
    public func verdict(
        for actor: CrimeActor,
        reference: RecordOwnership?,
        cell: RecordOwnership?
    ) -> OwnershipVerdict {
        verdict(for: actor, owner: owner(reference: reference, cell: cell))
    }

    public init(factions: FactionStore, pluginName: String) {
        self.factions = factions
        self.pluginName = pluginName
    }
}
