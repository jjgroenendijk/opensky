import Foundation
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// Why an arrest outcome could not run.
nonisolated public enum ArrestRefusal: Error, Equatable, Sendable {
    /// The player owes this faction nothing.
    case noBounty
    /// The player's gold does not cover the bounty.
    case cannotAfford(owed: Int32, gold: Int32)
}

/// What one arrest outcome did.
nonisolated public struct ArrestSettlement: Equatable, Sendable {
    public let faction: ReferenceKey
    /// The bounty that was cleared.
    public let bounty: Int32
    /// Gold taken from the player; zero for a jail sentence.
    public let goldPaid: Int32
    /// Stolen stacks that went to the evidence chest.
    public let confiscated: [InventoryStack]
    /// Where they went, or nil when nothing moved.
    public let evidenceChest: ReferenceKey?
    /// Days served; zero for a paid fine.
    public let sentenceDays: Int
    /// Where the player should stand afterwards: the faction's exterior jail
    /// marker for a sentence or a pay-and-go-to-jail, nil otherwise.
    public let releaseMarker: ReferenceKey?

    public init(
        faction: ReferenceKey,
        bounty: Int32,
        goldPaid: Int32,
        confiscated: [InventoryStack],
        evidenceChest: ReferenceKey?,
        sentenceDays: Int,
        releaseMarker: ReferenceKey?
    ) {
        self.faction = faction
        self.bounty = bounty
        self.goldPaid = goldPaid
        self.confiscated = confiscated
        self.evidenceChest = evidenceChest
        self.sentenceDays = sentenceDays
        self.releaseMarker = releaseMarker
    }
}

/// What reporting one crime did, and why.
nonisolated public struct CrimeOutcome: Equatable, Sendable {
    /// Why a crime accrued no gold, when it accrued none.
    public enum Refusal: String, Equatable, Sendable {
        /// The place belongs to no crime faction, so there is nobody to charge.
        case noCrimeFaction
        /// This load order carries no FACT for the resolved crime faction.
        case unresolvedCrimeFaction
        /// The faction does not have `trackCrime` set.
        case factionIgnoresCrime
        /// The faction sets the ignore bit for this kind of crime.
        case factionIgnoresKind
        /// The faction does not report crimes against its own members, and the
        /// victim is one.
        case victimIsMember
        /// Nobody saw it.
        case unwitnessed
    }

    /// Gold added to the ledger, which is zero for every refusal.
    public let gold: Int32
    /// The faction charged, or nil when nothing was charged.
    public let faction: ReferenceKey?
    /// Whether the crime was counted at all, which is false only when there was
    /// no faction to count it against.
    public let recorded: Bool
    /// Why no gold was charged, or nil when some was.
    public let refusal: Refusal?

    /// Nothing happened, for a crime that reached no faction.
    public static func refused(_ refusal: Refusal, faction: ReferenceKey? = nil) -> CrimeOutcome {
        CrimeOutcome(
            gold: 0,
            faction: faction,
            recorded: faction != nil && refusal != .unresolvedCrimeFaction,
            refusal: refusal
        )
    }

    public init(gold: Int32, faction: ReferenceKey?, recorded: Bool, refusal: Refusal?) {
        self.gold = gold
        self.faction = faction
        self.recorded = recorded
        self.refusal = refusal
    }
}

/// Everything about the running session a crime needs to know.
@MainActor
public protocol CrimeWorld: AnyObject {
    /// The owner in force for one resident reference: its own `XOWN`, else the
    /// owner of the cell it stands in (`OwnershipResolver`). Nil when nothing
    /// claims it, and also when nothing resident is that reference — a
    /// reference the session cannot see is not one it can call owned.
    func crimeOwner(of key: ReferenceKey) -> ReferenceOwner?

    /// The crime faction answering for `cell`, walking the location parent
    /// chain (`CrimeFactionResolver`). Nil where the place belongs to nobody.
    func crimeFaction(in cell: CellSceneLocation?) -> ReferenceKey?

    /// Which cell a resident reference stands in, so a crime is attributed to
    /// the cell whose rebuild makes it visible.
    func crimeCell(of key: ReferenceKey) -> CellSceneLocation?

    /// One item's authored gold value, which is what a theft bounty is scaled
    /// from. Zero for a form no loaded plugin describes — the same answer
    /// `InventoryRuntime.carriedValue` gives, because inventing a value would
    /// put a number the data never authored into a bounty.
    func crimeItemValue(of item: FormID) -> Int64

    /// Who is acting, with the memberships an ownership check needs.
    func crimeActor(_ key: ReferenceKey) -> CrimeActor
}

/// Who polices what.
nonisolated public enum GuardRecognition: Sendable {
    /// The crime faction `profile` polices, or nil when it is not a guard.
    ///
    /// Membership in the guard faction is what makes a guard; `CRIF` is which
    /// hold it answers for. A guard with no `CRIF` polices nothing, and a load
    /// order with no `GFAC` has no guards at all.
    public static func policedFaction(
        of profile: ActorSocialProfile,
        guardFaction: ReferenceKey?
    ) -> ReferenceKey? {
        guard
            let guardFaction,
            let crimeFaction = profile.crimeFaction,
            profile.memberships.isMember(of: guardFaction)
        else { return nil }
        return crimeFaction
    }
}

/// One `XOWN`/`XRNK` pair as the records carry it, before anything resolves
/// which kind of record the link names.
///
/// A plain pair rather than two loose parameters because the two are read
/// together at every site and a rank without its owner means nothing.
nonisolated public struct RecordOwnership: Equatable, Sendable {
    /// `XOWN` — the NPC_ or FACT this reference or cell belongs to.
    public let owner: FormID
    /// `XRNK` — the rank a faction member needs, or nil when the field is
    /// absent.
    public let requiredRank: Int32?

    public init(owner: FormID, requiredRank: Int32? = nil) {
        self.owner = owner
        self.requiredRank = requiredRank
    }

    /// The pair one placed reference authors, or nil when it authors no owner.
    public init?(reference: PlacedReference) {
        guard let owner = reference.owner, !owner.isNull else { return nil }
        self.init(owner: owner, requiredRank: reference.ownerFactionRank)
    }

    /// The pair one cell authors, which is what a reference with no `XOWN` of
    /// its own inherits.
    public init?(cell: Cell) {
        guard let owner = cell.owner, !owner.isNull else { return nil }
        self.init(owner: owner, requiredRank: cell.ownerFactionRank)
    }
}

/// Who a reference belongs to, once the link has been resolved to a record.
nonisolated public enum ReferenceOwner: Equatable, Sendable {
    /// An NPC_ base owns it. The key is that base's runtime identity, not a
    /// placed actor's: `XOWN` names the base record, and every ACHR placed from
    /// it is the same owner.
    case actor(ReferenceKey)
    /// A faction owns it, and a member needs at least `requiredRank` before it
    /// is theirs to use.
    case faction(ReferenceKey, requiredRank: Int32)

    /// The owning record's identity, whichever kind it is.
    public var key: ReferenceKey {
        switch self {
        case let .actor(key): key
        case let .faction(key, _): key
        }
    }
}

/// What one actor may do with one reference.
nonisolated public enum OwnershipVerdict: Equatable, Sendable {
    /// Nothing claims it, so taking it is not theft.
    case unowned
    /// Somebody claims it and this actor is that somebody, or ranks high enough
    /// in the faction that does.
    case permitted(ReferenceOwner)
    /// Somebody else claims it. Taking it is theft.
    case forbidden(ReferenceOwner)

    /// The owner, or nil when nothing claims the reference.
    public var owner: ReferenceOwner? {
        switch self {
        case .unowned: nil
        case let .permitted(owner), let .forbidden(owner): owner
        }
    }

    /// Whether taking this reference would be a theft.
    public var isTheft: Bool {
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
nonisolated public struct CrimeActor: Equatable, Sendable {
    /// The NPC_ base this actor was placed from, or nil for the player, who has
    /// no base record in this engine (`ReferenceKey.player`).
    public let base: ReferenceKey?
    /// Everything the actor currently belongs to, which is what a faction-owned
    /// reference is checked against.
    public let memberships: ActorFactionState

    public init(
        base: ReferenceKey? = nil,
        memberships: ActorFactionState = ActorFactionState()
    ) {
        self.base = base
        self.memberships = memberships
    }

    /// The player with no memberships, which is what a synthetic scene and a
    /// fresh session both start from.
    public static let player = CrimeActor()

    /// Whether property owned by `owner` is this actor's to use. An actor owner
    /// matches the NPC_ base, so the player matches none. A faction owner matches a
    /// member at or above the required rank. The one place this rule lives.
    public func mayUse(_ owner: ReferenceOwner) -> Bool {
        switch owner {
        case let .actor(base):
            self.base == base
        case let .faction(faction, requiredRank):
            memberships.rank(in: faction).map { Int32($0) >= requiredRank } ?? false
        }
    }

    /// What this actor may do with a reference owned by `owner`.
    public func verdict(on owner: ReferenceOwner?) -> OwnershipVerdict {
        guard let owner else { return .unowned }
        return mayUse(owner) ? .permitted(owner) : .forbidden(owner)
    }
}

/// The `XOWN`/`XRNK` reading for one placed reference, and what the crime
/// runtime makes of it. Shown on the gate panel.
nonisolated public struct ReferenceOwnershipReadout: Equatable, Sendable {
    /// How the reference is named in the world, matching the HUD prompt.
    public let name: String
    public let reference: FormID
    /// `XOWN` — the owning NPC_ or FACT, nil when the reference itself is
    /// unowned. A reference with none may still be owned through its cell,
    /// which `isTheft` accounts for and this field does not.
    public let owner: FormID?
    /// `XRNK` — the faction rank required to use it freely. Meaningful only
    /// when `owner` is a FACT; nil when the field is absent.
    public let factionRank: Int32?
    /// Whether taking it would be theft for the player now: the `OwnershipVerdict`
    /// over the reference, its cell, and the player's memberships. Differs from
    /// `isOwned`: an item in an owned shop has no `XOWN` but is still theft.
    public let isTheft: Bool
    /// What taking it would add to the bounty, in gold. Zero when the take is
    /// no crime, and also when the place answers to no crime faction.
    public let bounty: Int32

    public init(
        name: String,
        reference: FormID,
        owner: FormID?,
        factionRank: Int32?,
        isTheft: Bool = false,
        bounty: Int32 = 0
    ) {
        self.name = name
        self.reference = reference
        self.owner = owner
        self.factionRank = factionRank
        self.isTheft = isTheft
        self.bounty = bounty
    }

    /// Whether the reference record itself names an owner.
    public var isOwned: Bool {
        owner != nil
    }
}
