// What a crime is, and what one is worth (issue #504, roadmap item 21.5).
//
// ## The four kinds
//
// Theft, assault, murder and trespass — the four the FACT `CRVA` struct prices
// and the four this milestone can actually observe happening. `CRVA` prices two
// more, pickpocketing and jailbreak escape, and the load order carries
// `iCrimeGoldStealHorse` and `iCrimeGoldWerewolf` for two others (observed on
// this install: 100 and 1000; they are the only two `iCrime*` settings that
// exist at all). None of those four has a mechanism behind it yet, so none is a
// case here: an enum case nothing can raise is a promise the engine does not
// keep. See docs/engine/crime.md for what that defers.
//
// ## Where the numbers come from
//
// Per crime faction, from its `CRVA` block, never from a game setting. That is
// not a simplification: `openskycli gmst list --prefix iCrime` on this install
// reports exactly two settings, neither of which prices any of these four,
// while `CrimeFactionWhiterun`'s `CRVA` reads "murder 1000, assault 40,
// trespass 5, pickpocket 25, steal multiplier 0.5000, escape 100, werewolf
// 1000". UESP's bounty table gives the same four numbers from the player's side
// — "Assault ... 40", "Trespassing ... 5", "Murder ... 1000", and stealing
// costs "Half of the stolen item's value, rounded down"
// (<https://en.uesp.net/wiki/Skyrim:Crime>) — which is the 0.5 steal
// multiplier applied to the item's value and rounded down.
//
// Documented in docs/engine/crime.md.

import Foundation

/// One kind of crime the engine can witness happening.
nonisolated enum CrimeKind: String, CaseIterable, Equatable, Sendable, Comparable {
    /// Taking a reference somebody else owns, whether off the ground or out of
    /// their container.
    case theft
    /// The first blow against an actor that was not already hostile.
    case assault
    /// That actor dying of it.
    case murder
    /// Being somewhere an owner has not let this actor be.
    case trespass

    /// Report ordering, which is also the order the save writes counts in.
    static func < (lhs: Self, rhs: Self) -> Bool {
        guard
            let left = allCases.firstIndex(of: lhs),
            let right = allCases.firstIndex(of: rhs)
        else { return false }
        return left < right
    }

    /// The FACT flag that makes this faction ignore the crime entirely.
    ///
    /// Bit names and values are xEdit's `wbFACT` DATA flags, which UESP's FACT
    /// page spells identically; `Faction.Flags` carries them.
    var ignoreFlag: Faction.Flags {
        switch self {
        case .theft: .ignoreStealing
        case .assault: .ignoreAssault
        case .murder: .ignoreMurder
        case .trespass: .ignoreTrespass
        }
    }

    /// How a readout names it.
    var label: String {
        rawValue.capitalized
    }
}

/// One crime, fully described: who did it, to whom, where, who answers for it,
/// and whether anybody saw.
///
/// A value rather than a call with six arguments, so the thing that happened
/// can be built at the site that noticed it, carried, logged and replayed. The
/// crime faction is already resolved: only the caller knows which cell the act
/// happened in, and `CrimeFactionResolver` turns that into a faction once
/// rather than at every consumer.
nonisolated struct CrimeEvent: Equatable, Sendable {
    let kind: CrimeKind
    /// Who committed it. The player in every path this milestone builds; the
    /// field is general because a follower commanded to steal is the same event
    /// with a different perpetrator.
    let perpetrator: ReferenceKey
    /// The owner robbed or the actor struck, or nil for a crime with no
    /// individual victim — a trespass against a faction-owned building.
    let victim: ReferenceKey?
    /// The crime faction that answers for the place this happened, or nil where
    /// none does. A crime in the wilderness accrues no bounty for exactly this
    /// reason, which is why a bandit killed on the road costs nothing.
    let crimeFaction: ReferenceKey?
    /// Cell the act happened in, so the ledger write is attributed to the cell
    /// whose rebuild made it visible.
    let cell: CellSceneLocation?
    /// Whether a live witness detected the perpetrator as it happened.
    ///
    /// Resolved by the caller through `CrimeWitnessSource` rather than here,
    /// because witnessing is a perception question and this is a value type.
    let witnessed: Bool
    /// Total gold value of what was taken, before the steal multiplier. Zero
    /// for every kind but theft.
    let stolenValue: Int64

    init(
        kind: CrimeKind,
        perpetrator: ReferenceKey,
        victim: ReferenceKey? = nil,
        crimeFaction: ReferenceKey? = nil,
        cell: CellSceneLocation? = nil,
        witnessed: Bool = false,
        stolenValue: Int64 = 0
    ) {
        self.kind = kind
        self.perpetrator = perpetrator
        self.victim = victim
        self.crimeFaction = crimeFaction
        self.cell = cell
        self.witnessed = witnessed
        self.stolenValue = stolenValue
    }
}

/// The bounty one faction charges for one crime, from its `CRVA` block.
nonisolated struct CrimeGoldTable: Equatable, Sendable {
    /// Multiplier used when the record's `CRVA` is too short to carry one.
    ///
    /// `Faction.CrimeValues.stealMultiplier` is optional because the field
    /// arrived in a later record version, and `Faction.swift` leaves what an
    /// absent one means to this issue. It means 1: the neutral multiplier, so a
    /// plugin writing a 12-byte `CRVA` charges the item's full value rather
    /// than nothing. Zero was the alternative and is the damaging one — it
    /// would make every theft from such a faction free.
    static let defaultStealMultiplier: Float = 1

    let values: Faction.CrimeValues?

    /// Nothing priced, which is what a faction with no `CRVA` charges: zero for
    /// every kind, and the crime is still counted.
    static let unpriced = CrimeGoldTable(values: nil)

    init(values: Faction.CrimeValues?) {
        self.values = values
    }

    init(faction: Faction) {
        self.init(values: faction.crimeValues)
    }

    /// What `event` costs, in gold.
    ///
    /// Theft is the value of what was taken times the steal multiplier, rounded
    /// down — "Half of the stolen item's value, rounded down"
    /// (<https://en.uesp.net/wiki/Skyrim:Crime>) with the 0.5 coming from the
    /// record rather than from the prose. Rounding down is what makes a
    /// one-gold trinket free, which is the behaviour the source describes;
    /// nothing here invents a floor.
    ///
    /// The other three are flat `CRVA` amounts.
    func bounty(for event: CrimeEvent) -> Int32 {
        guard let values else { return 0 }
        return switch event.kind {
        case .theft: Self.stealBounty(of: event.stolenValue, multiplier: values.stealMultiplier)
        case .assault: Int32(values.assault)
        case .murder: Int32(values.murder)
        case .trespass: Int32(values.trespass)
        }
    }

    /// The theft amount on its own, so a readout can price a take before it
    /// happens.
    ///
    /// Computed in `Double` and clamped into `Int32`: a mod may author a large
    /// multiplier, and a stack of a thousand jewels times it must saturate
    /// rather than wrap into a negative bounty.
    static func stealBounty(of value: Int64, multiplier: Float?) -> Int32 {
        let factor = multiplier ?? defaultStealMultiplier
        guard value > 0, factor.isFinite, factor > 0 else { return 0 }
        return Int32(clamping: Int64((Double(value) * Double(factor)).rounded(.down)))
    }
}
