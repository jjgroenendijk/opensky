// The bounty ledger, as a world-state component (issue #504, roadmap item
// 21.5): what one actor owes each crime faction, and how many of each crime it
// has committed against them.
//
// A slot of its own beside `factions` and `playerProgress`, for the lifetime
// reason those two are separate from `actorValues`: a bounty moves when a crime
// is witnessed, while the values beside it are rewritten sixty times a second.
//
// ## Per faction, not per hold
//
// "Bounties are tracked separately for each of Skyrim's nine holds and you will
// only incur a bounty in the hold in which you commit a crime ... The
// Companions, the Tribal Orc strongholds, and Raven Rock each track bounties
// independently" (<https://en.uesp.net/wiki/Skyrim:Crime>). A hold is not a
// concept this engine has; a crime faction is, and the twelve the source names
// are twelve crime factions. Keying by faction is therefore the general shape
// and the vanilla one at once, and it is what a `Faction.GetCrimeGold` call
// asks for.
//
// ## Counts as well as gold
//
// "Regardless of whether a crime is witnessed, the Statistics tab on the menu
// keeps track of all your criminal activities" (same page). So an unwitnessed
// theft leaves a count and no gold, which is exactly the difference the
// acceptance test pins.
//
// The component is dropped once it empties, as `PerkState` and
// `ActorFactionState` are, so a law-abiding session stays clean.
//
// Documented in docs/engine/bounty-ledger.md.

import Foundation
import OpenSkyFormatsESM

/// How many of each kind of crime one actor has committed against one faction.
///
/// Explicit fields rather than a dictionary so the save writes the same bytes
/// twice for the same state, which is the rule every component here follows.
nonisolated public struct CrimeCounts: Equatable, Sendable {
    public private(set) var theft: Int32
    public private(set) var assault: Int32
    public private(set) var murder: Int32
    public private(set) var trespass: Int32

    public static let none = CrimeCounts()

    /// Clamped on the way in, which is what makes this the save decoder's entry
    /// point: a negative count from a corrupt file becomes zero rather than a
    /// number that reads as "minus three murders".
    public init(theft: Int32 = 0, assault: Int32 = 0, murder: Int32 = 0, trespass: Int32 = 0) {
        self.theft = max(0, theft)
        self.assault = max(0, assault)
        self.murder = max(0, murder)
        self.trespass = max(0, trespass)
    }

    public var isEmpty: Bool {
        self == CrimeCounts()
    }

    /// Every crime of every kind.
    public var total: Int64 {
        Int64(theft) + Int64(assault) + Int64(murder) + Int64(trespass)
    }

    public subscript(kind: CrimeKind) -> Int32 {
        switch kind {
        case .theft: theft
        case .assault: assault
        case .murder: murder
        case .trespass: trespass
        }
    }

    /// These counts with one more of `kind`. Saturating rather than wrapping:
    /// a session long enough to overflow `Int32` murders should report
    /// `Int32.max` rather than a negative number.
    public func incrementing(_ kind: CrimeKind) -> CrimeCounts {
        let raised = Int32(clamping: Int64(self[kind]) + 1)
        var result = self
        switch kind {
        case .theft: result.theft = raised
        case .assault: result.assault = raised
        case .murder: result.murder = raised
        case .trespass: result.trespass = raised
        }
        return result
    }
}

/// One faction's row: what is owed and what was done.
///
/// The gold is held in two halves, violent and non-violent, because that is
/// how the Creation Kit surface asks about it: `GetCrimeGoldViolent` and
/// `GetCrimeGoldNonviolent` are separate condition functions, and
/// `Faction.ModCrimeGold` takes an `abViolent` flag. `gold` is their sum,
/// which is what `GetCrimeGold` and a guard's fine both mean.
nonisolated public struct CrimeLedgerEntry: Equatable, Sendable, Comparable {
    public let faction: ReferenceKey
    /// Crime gold outstanding for non-violent crimes — theft and trespass.
    /// Never negative: a bounty is paid down to zero, never past it.
    public let nonViolentGold: Int32
    /// Crime gold outstanding for violent crimes — assault and murder.
    public let violentGold: Int32
    public let counts: CrimeCounts

    public init(
        faction: ReferenceKey,
        nonViolentGold: Int32 = 0,
        violentGold: Int32 = 0,
        counts: CrimeCounts = .none
    ) {
        self.faction = faction
        self.nonViolentGold = max(0, nonViolentGold)
        self.violentGold = max(0, violentGold)
        self.counts = counts
    }

    /// Everything owed to this faction, saturating rather than wrapping.
    public var gold: Int32 {
        Int32(clamping: Int64(nonViolentGold) + Int64(violentGold))
    }

    /// One half of the gold.
    public func gold(violent: Bool) -> Int32 {
        violent ? violentGold : nonViolentGold
    }

    /// True when the row records nothing, which is when it is dropped.
    public var isEmpty: Bool {
        nonViolentGold == 0 && violentGold == 0 && counts.isEmpty
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.faction < rhs.faction
    }

    /// This row with one half of the gold replaced.
    fileprivate func setting(_ amount: Int32, violent: Bool, counts: CrimeCounts? = nil) -> Self {
        CrimeLedgerEntry(
            faction: faction,
            nonViolentGold: violent ? nonViolentGold : amount,
            violentGold: violent ? amount : violentGold,
            counts: counts ?? self.counts
        )
    }
}

/// Everything one actor owes, in ascending faction-key order.
nonisolated public struct CrimeLedgerState: WorldStateComponent, Sendable {
    /// One row per faction, sorted by faction key, none of them empty.
    public private(set) var entries: [CrimeLedgerEntry]

    public static let empty = CrimeLedgerState()

    public static var componentKind: WorldStateComponentKind {
        .crimeLedger
    }

    /// Normalizes on the way in, which is what makes this the save decoder's
    /// entry point: a repeated faction collapses to its last row, empty rows
    /// drop out, and the order becomes key order, so a file written under a
    /// different load order still restores a valid component.
    ///
    /// A faction this load order no longer resolves is *kept*, the rule a
    /// stored membership and an owned perk follow: a bounty is progress the
    /// player made, and losing it because a plugin came and went would be the
    /// damaging direction to fail in.
    public init(entries: [CrimeLedgerEntry] = []) {
        var rows: [ReferenceKey: CrimeLedgerEntry] = [:]
        for entry in entries where !entry.isEmpty {
            rows[entry.faction] = entry
        }
        self.entries = rows.keys.sorted().compactMap { rows[$0] }
    }

    // MARK: - Reading

    public var isEmpty: Bool {
        entries.isEmpty
    }

    public var count: Int {
        entries.count
    }

    /// Every faction this actor owes something to or has offended, in key
    /// order.
    public var factions: [ReferenceKey] {
        entries.map(\.faction)
    }

    public func entry(for faction: ReferenceKey) -> CrimeLedgerEntry? {
        entries.first { $0.faction == faction }
    }

    /// Crime gold owed to one faction, both halves together; 0 when there is
    /// no row, which is not a different answer from a row that has been paid
    /// off.
    public func gold(for faction: ReferenceKey) -> Int32 {
        entry(for: faction)?.gold ?? 0
    }

    /// One half of what is owed to one faction.
    public func gold(for faction: ReferenceKey, violent: Bool) -> Int32 {
        entry(for: faction)?.gold(violent: violent) ?? 0
    }

    public func counts(for faction: ReferenceKey) -> CrimeCounts {
        entry(for: faction)?.counts ?? .none
    }

    /// Total gold owed everywhere, which is UESP's "Total Lifetime Bounty"
    /// read across the rows rather than stored a second time.
    public var totalGold: Int64 {
        entries.reduce(0) { $0 + Int64($1.gold) }
    }

    /// How many crimes of one kind this actor has committed anywhere.
    public func totalCount(of kind: CrimeKind) -> Int64 {
        entries.reduce(0) { $0 + Int64($1.counts[kind]) }
    }

    // MARK: - Deriving

    /// This ledger with one more crime of `kind` against `faction`, and `gold`
    /// added to the half `kind` belongs to.
    ///
    /// Both halves move in one call because a crime is one fact: recording the
    /// count and the gold separately is two chances for them to disagree.
    public func recording(_ kind: CrimeKind, gold: Int32, against faction: ReferenceKey) -> Self {
        let existing = entry(for: faction) ?? CrimeLedgerEntry(faction: faction)
        let violent = kind.isViolent
        return replacing(existing.setting(
            Self.saturatingSum(existing.gold(violent: violent), max(0, gold)),
            violent: violent,
            counts: existing.counts.incrementing(kind)
        ))
    }

    /// This ledger with one half of `faction`'s gold moved by `delta`, clamped
    /// at zero and leaving the counts alone.
    ///
    /// The door `Faction.ModCrimeGold` comes through, which is why it does not
    /// touch the counts: paying a bounty settles the debt and does not
    /// un-commit the crime.
    public func modifyingGold(
        by delta: Int32,
        violent: Bool = false,
        for faction: ReferenceKey
    ) -> Self {
        let existing = entry(for: faction) ?? CrimeLedgerEntry(faction: faction)
        return settingGold(
            Self.saturatingSum(existing.gold(violent: violent), delta),
            violent: violent,
            for: faction
        )
    }

    /// This ledger with one half of `faction`'s gold set outright, leaving the
    /// other half and the counts alone. `Faction.SetCrimeGold` sets the
    /// non-violent half and `Faction.SetCrimeGoldViolent` the violent one.
    public func settingGold(
        _ gold: Int32,
        violent: Bool = false,
        for faction: ReferenceKey
    ) -> Self {
        let existing = entry(for: faction) ?? CrimeLedgerEntry(faction: faction)
        return replacing(existing.setting(max(0, gold), violent: violent))
    }

    /// This ledger with both halves of `faction`'s gold at zero and the counts
    /// kept. What paying a fine or serving the sentence does.
    public func clearingGold(for faction: ReferenceKey) -> Self {
        settingGold(0, violent: true, for: faction).settingGold(0, violent: false, for: faction)
    }

    // MARK: - Private

    /// This ledger with `entry` in place of whatever row that faction had,
    /// dropping the row entirely when it says nothing.
    private func replacing(_ entry: CrimeLedgerEntry) -> Self {
        CrimeLedgerState(entries: entries.filter { $0.faction != entry.faction } + [entry])
    }

    /// `left + right` clamped into `Int32` and floored at zero, so a mod adding
    /// a billion-gold bounty saturates instead of wrapping negative.
    private static func saturatingSum(_ left: Int32, _ right: Int32) -> Int32 {
        Int32(clamping: max(0, Int64(left) + Int64(right)))
    }
}

nonisolated extension WorldStateComponentKind {
    /// What one actor owes each crime faction, and how many of each crime it has
    /// committed against them. Like `playerProgress` it modifies no placement and
    /// belongs to no cell in practice: it is keyed by the perpetrator, which is
    /// `ReferenceKey.player` for every path this milestone builds. A slot of its
    /// own beside `factions` for the reason `perks` is one — a bounty moves when a
    /// crime is witnessed, while the actor values beside it are rewritten sixty
    /// times a second.
    public static let crimeLedger = Self(rawValue: "crimeLedger", order: 19)
}

nonisolated extension WorldStateComponentValue {
    public static func crimeLedger(_ value: CrimeLedgerState) -> Self {
        Self(value)
    }
}
