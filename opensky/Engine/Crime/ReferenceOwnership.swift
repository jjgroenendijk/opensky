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

/// One `XOWN`/`XRNK` pair as the records carry it, before anything resolves
/// which kind of record the link names.
///
/// A plain pair rather than two loose parameters because the two are read
/// together at every site and a rank without its owner means nothing.
nonisolated struct RecordOwnership: Equatable, Sendable {
    /// `XOWN` — the NPC_ or FACT this reference or cell belongs to.
    let owner: FormID
    /// `XRNK` — the rank a faction member needs, or nil when the field is
    /// absent.
    let requiredRank: Int32?

    init(owner: FormID, requiredRank: Int32? = nil) {
        self.owner = owner
        self.requiredRank = requiredRank
    }

    /// The pair one placed reference authors, or nil when it authors no owner.
    init?(reference: PlacedReference) {
        guard let owner = reference.owner, !owner.isNull else { return nil }
        self.init(owner: owner, requiredRank: reference.ownerFactionRank)
    }

    /// The pair one cell authors, which is what a reference with no `XOWN` of
    /// its own inherits.
    init?(cell: Cell) {
        guard let owner = cell.owner, !owner.isNull else { return nil }
        self.init(owner: owner, requiredRank: cell.ownerFactionRank)
    }
}

/// Who a reference belongs to, once the link has been resolved to a record.
nonisolated enum ReferenceOwner: Equatable, Sendable {
    /// An NPC_ base owns it. The key is that base's runtime identity, not a
    /// placed actor's: `XOWN` names the base record, and every ACHR placed from
    /// it is the same owner.
    case actor(ReferenceKey)
    /// A faction owns it, and a member needs at least `requiredRank` before it
    /// is theirs to use.
    case faction(ReferenceKey, requiredRank: Int32)

    /// The owning record's identity, whichever kind it is.
    var key: ReferenceKey {
        switch self {
        case let .actor(key): key
        case let .faction(key, _): key
        }
    }
}

/// What one actor may do with one reference.
nonisolated enum OwnershipVerdict: Equatable, Sendable {
    /// Nothing claims it, so taking it is not theft.
    case unowned
    /// Somebody claims it and this actor is that somebody, or ranks high enough
    /// in the faction that does.
    case permitted(ReferenceOwner)
    /// Somebody else claims it. Taking it is theft.
    case forbidden(ReferenceOwner)

    /// The owner, or nil when nothing claims the reference.
    var owner: ReferenceOwner? {
        switch self {
        case .unowned: nil
        case let .permitted(owner), let .forbidden(owner): owner
        }
    }

    /// Whether taking this reference would be a theft.
    var isTheft: Bool {
        if case .forbidden = self {
            return true
        }
        return false
    }
}

/// The acting side of an ownership question: who is reaching for the thing.
///
/// A value rather than an `ActorValueHolder` because ownership needs exactly
/// two facts — which NPC_ record this actor is, and what it is a member of —
/// and a caller holding a save-decoded membership list has both without a live
/// actor behind them.
nonisolated struct CrimeActor: Equatable, Sendable {
    /// Runtime identity of the acting reference.
    let key: ReferenceKey
    /// The NPC_ base this actor was placed from, or nil for the player, who has
    /// no base record in this engine (`ReferenceKey.player`).
    let base: ReferenceKey?
    /// Everything the actor currently belongs to, which is what a faction-owned
    /// reference is checked against.
    let memberships: ActorFactionState

    init(
        key: ReferenceKey,
        base: ReferenceKey? = nil,
        memberships: ActorFactionState = ActorFactionState()
    ) {
        self.key = key
        self.base = base
        self.memberships = memberships
    }

    /// The player with no memberships, which is what a synthetic scene and a
    /// fresh session both start from.
    static let player = CrimeActor(key: .player)

    /// Whether property owned by `owner` is this actor's to use.
    ///
    /// An actor owner matches on the NPC_ base, because that is what `XOWN`
    /// names: every ACHR placed from the owning base is the owner, and an actor
    /// with no base — the player — matches none of them. A faction owner
    /// matches a member at or above the rank the record demands.
    ///
    /// The one place the rule lives, so `OwnershipResolver` and `CrimeReporter`
    /// cannot drift apart on it.
    func mayUse(_ owner: ReferenceOwner) -> Bool {
        switch owner {
        case let .actor(base):
            self.base == base
        case let .faction(faction, requiredRank):
            memberships.rank(in: faction).map { Int32($0) >= requiredRank } ?? false
        }
    }

    /// What this actor may do with a reference owned by `owner`.
    func verdict(on owner: ReferenceOwner?) -> OwnershipVerdict {
        guard let owner else { return .unowned }
        return mayUse(owner) ? .permitted(owner) : .forbidden(owner)
    }
}

/// Resolves `XOWN` links against the load order and answers the ownership
/// question over them.
///
/// A value snapshot rather than a live handle, the shape every other
/// record-reading seam in this engine takes: it holds the FACT store and the
/// plugin the links are spelled against, and answers are pure functions of the
/// arguments.
nonisolated struct OwnershipResolver {
    /// Rank an owning faction demands when the record authors no `XRNK`.
    ///
    /// Zero, the lowest rank vanilla authors — `ActorFactionMembership.rank` is
    /// signed precisely so a negative rank can mean "a member the rank titles
    /// do not name", and an ordinary rank-0 member of the owning faction is
    /// exactly who a shop's back room is meant to be open to.
    static let defaultRequiredRank: Int32 = 0

    /// Load-order FACT lookup, which is what distinguishes a faction owner from
    /// an actor owner.
    let factions: FactionStore
    /// The plugin `XOWN` links are relative to.
    let pluginName: String

    /// The owner one `XOWN`/`XRNK` pair names.
    ///
    /// A link the load order carries a FACT for is a faction owner; anything
    /// else is an actor owner, including a link nothing resolves — a dangling
    /// owner is still a claim, and reading it as "unowned" would quietly make
    /// a shop free to loot when a plugin went missing. A link whose *plugin* is
    /// not loaded resolves to nothing at all and is the one case that reports
    /// nil.
    func owner(of ownership: RecordOwnership) -> ReferenceOwner? {
        guard let resolved = factions.resolvedID(ownership.owner, fromPlugin: pluginName) else {
            return nil
        }
        let key = ReferenceKey(resolved: resolved)
        guard factions.faction(key: key) != nil else { return .actor(key) }
        return .faction(key, requiredRank: ownership.requiredRank ?? Self.defaultRequiredRank)
    }

    /// The owner in force for a reference, applying the reference-then-cell
    /// precedence.
    func owner(reference: RecordOwnership?, cell: RecordOwnership?) -> ReferenceOwner? {
        if let reference, let owner = owner(of: reference) {
            return owner
        }
        guard let cell else { return nil }
        return owner(of: cell)
    }

    /// What `actor` may do with a reference owned by `owner`.
    func verdict(for actor: CrimeActor, owner: ReferenceOwner?) -> OwnershipVerdict {
        actor.verdict(on: owner)
    }

    /// The whole question in one call: the two `XOWN` pairs in, a verdict out.
    func verdict(
        for actor: CrimeActor,
        reference: RecordOwnership?,
        cell: RecordOwnership?
    ) -> OwnershipVerdict {
        verdict(for: actor, owner: owner(reference: reference, cell: cell))
    }
}
