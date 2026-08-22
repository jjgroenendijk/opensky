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
// Documented in docs/engine/crime.md.

import Foundation

/// How many of each kind of crime one actor has committed against one faction.
///
/// Explicit fields rather than a dictionary so the save writes the same bytes
/// twice for the same state, which is the rule every component here follows.
nonisolated struct CrimeCounts: Equatable, Sendable {
    private(set) var theft: Int32
    private(set) var assault: Int32
    private(set) var murder: Int32
    private(set) var trespass: Int32

    static let none = CrimeCounts()

    /// Clamped on the way in, which is what makes this the save decoder's entry
    /// point: a negative count from a corrupt file becomes zero rather than a
    /// number that reads as "minus three murders".
    init(theft: Int32 = 0, assault: Int32 = 0, murder: Int32 = 0, trespass: Int32 = 0) {
        self.theft = max(0, theft)
        self.assault = max(0, assault)
        self.murder = max(0, murder)
        self.trespass = max(0, trespass)
    }

    var isEmpty: Bool {
        self == CrimeCounts()
    }

    /// Every crime of every kind.
    var total: Int64 {
        Int64(theft) + Int64(assault) + Int64(murder) + Int64(trespass)
    }

    subscript(kind: CrimeKind) -> Int32 {
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
    func incrementing(_ kind: CrimeKind) -> CrimeCounts {
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
nonisolated struct CrimeLedgerEntry: Equatable, Sendable, Comparable {
    let faction: ReferenceKey
    /// Crime gold outstanding with this faction. Never negative — a bounty is
    /// paid down to zero, never past it.
    let gold: Int32
    let counts: CrimeCounts

    init(faction: ReferenceKey, gold: Int32 = 0, counts: CrimeCounts = .none) {
        self.faction = faction
        self.gold = max(0, gold)
        self.counts = counts
    }

    /// True when the row records nothing, which is when it is dropped.
    var isEmpty: Bool {
        gold == 0 && counts.isEmpty
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.faction < rhs.faction
    }
}

/// Everything one actor owes, in ascending faction-key order.
nonisolated struct CrimeLedgerState: WorldStateComponent {
    /// One row per faction, sorted by faction key, none of them empty.
    private(set) var entries: [CrimeLedgerEntry]

    static let empty = CrimeLedgerState()

    static var componentKind: WorldStateComponentKind {
        .crimeLedger
    }

    var erased: WorldStateComponentValue {
        .crimeLedger(self)
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
    init(entries: [CrimeLedgerEntry] = []) {
        var rows: [ReferenceKey: CrimeLedgerEntry] = [:]
        for entry in entries where !entry.isEmpty {
            rows[entry.faction] = entry
        }
        self.entries = rows.keys.sorted().compactMap { rows[$0] }
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .crimeLedger(value) = erased else { return nil }
        self = value
    }

    // MARK: - Reading

    var isEmpty: Bool {
        entries.isEmpty
    }

    var count: Int {
        entries.count
    }

    /// Every faction this actor owes something to or has offended, in key
    /// order.
    var factions: [ReferenceKey] {
        entries.map(\.faction)
    }

    func entry(for faction: ReferenceKey) -> CrimeLedgerEntry? {
        entries.first { $0.faction == faction }
    }

    /// Crime gold owed to one faction; 0 when there is no row, which is not a
    /// different answer from a row that has been paid off.
    func gold(for faction: ReferenceKey) -> Int32 {
        entry(for: faction)?.gold ?? 0
    }

    func counts(for faction: ReferenceKey) -> CrimeCounts {
        entry(for: faction)?.counts ?? .none
    }

    /// Total gold owed everywhere, which is UESP's "Total Lifetime Bounty"
    /// read across the rows rather than stored a second time.
    var totalGold: Int64 {
        entries.reduce(0) { $0 + Int64($1.gold) }
    }

    /// How many crimes of one kind this actor has committed anywhere.
    func totalCount(of kind: CrimeKind) -> Int64 {
        entries.reduce(0) { $0 + Int64($1.counts[kind]) }
    }

    // MARK: - Deriving

    /// This ledger with one more crime of `kind` against `faction`, and `gold`
    /// added to what is owed.
    ///
    /// Both halves move in one call because a crime is one fact: recording the
    /// count and the gold separately is two chances for them to disagree.
    func recording(_ kind: CrimeKind, gold: Int32, against faction: ReferenceKey) -> Self {
        let existing = entry(for: faction) ?? CrimeLedgerEntry(faction: faction)
        return replacing(CrimeLedgerEntry(
            faction: faction,
            gold: Self.saturatingSum(existing.gold, max(0, gold)),
            counts: existing.counts.incrementing(kind)
        ))
    }

    /// This ledger with `faction`'s gold moved by `delta`, clamped at zero and
    /// leaving the counts alone.
    ///
    /// The door `Faction.ModCrimeGold` and a paid fine both come through, which
    /// is why it does not touch the counts: paying a bounty settles the debt
    /// and does not un-commit the crime.
    func modifyingGold(by delta: Int32, for faction: ReferenceKey) -> Self {
        let existing = entry(for: faction) ?? CrimeLedgerEntry(faction: faction)
        return settingGold(Self.saturatingSum(existing.gold, delta), for: faction)
    }

    /// This ledger with `faction`'s gold set outright, leaving the counts
    /// alone. The door `Faction.SetCrimeGold` comes through.
    func settingGold(_ gold: Int32, for faction: ReferenceKey) -> Self {
        let existing = entry(for: faction) ?? CrimeLedgerEntry(faction: faction)
        return replacing(CrimeLedgerEntry(
            faction: faction,
            gold: max(0, gold),
            counts: existing.counts
        ))
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
