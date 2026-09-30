// What a crime is, and what one is worth. Four kinds: theft, assault, murder,
// and trespass, the ones this engine can observe. Prices come from each crime
// faction's `CRVA`, not from game settings; they match UESP's bounty table
// (<https://en.uesp.net/wiki/Skyrim:Crime>). See docs/engine/crime.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One kind of crime the engine can witness happening.
nonisolated public enum CrimeKind: String, CaseIterable, Equatable, Sendable, Comparable {
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
    public static func < (lhs: Self, rhs: Self) -> Bool {
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
    public var ignoreFlag: Faction.Flags {
        switch self {
        case .theft: .ignoreStealing
        case .assault: .ignoreAssault
        case .murder: .ignoreMurder
        case .trespass: .ignoreTrespass
        }
    }

    /// Whether the bounty lands in the violent half of the ledger: the "Major
    /// Crimes" of <https://ck.uesp.net/wiki/Crime> (assault, murder).
    public var isViolent: Bool {
        switch self {
        case .assault, .murder: true
        case .theft, .trespass: false
        }
    }
}

/// One crime, fully described: who did it, to whom, where, who answers for it,
/// and whether anybody saw. The caller resolves the crime faction once.
nonisolated public struct CrimeEvent: Equatable, Sendable {
    public let kind: CrimeKind
    /// Who committed it. The player in every path this milestone builds; the
    /// field is general because a follower commanded to steal is the same event
    /// with a different perpetrator.
    public let perpetrator: ReferenceKey
    /// The owner robbed or the actor struck, or nil for a crime with no
    /// individual victim — a trespass against a faction-owned building.
    public let victim: ReferenceKey?
    /// The crime faction that answers for the place this happened, or nil where
    /// none does. A crime in the wilderness accrues no bounty for exactly this
    /// reason, which is why a bandit killed on the road costs nothing.
    public let crimeFaction: ReferenceKey?
    /// Cell the act happened in, so the ledger write is attributed to the cell
    /// whose rebuild made it visible.
    public let cell: CellSceneLocation?
    /// Whether a live witness detected the perpetrator as it happened.
    ///
    /// Resolved by the caller through `CrimeWitnessSource` rather than here,
    /// because witnessing is a perception question and this is a value type.
    public let witnessed: Bool
    /// Total gold value of what was taken, before the steal multiplier. Zero
    /// for every kind but theft.
    public let stolenValue: Int64

    public init(
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
nonisolated public struct CrimeGoldTable: Equatable, Sendable {
    /// Multiplier used when the record's `CRVA` is too short to carry one. It is 1,
    /// so a 12-byte `CRVA` charges full value; 0 would make every theft free.
    public static let defaultStealMultiplier: Float = 1

    public let values: Faction.CrimeValues?

    /// Nothing priced, which is what a faction with no `CRVA` charges: zero for
    /// every kind, and the crime is still counted.
    public static let unpriced = CrimeGoldTable(values: nil)

    public init(values: Faction.CrimeValues?) {
        self.values = values
    }

    public init(faction: Faction) {
        self.init(values: faction.crimeValues)
    }

    /// What `event` costs, in gold. Theft is the item value times the steal
    /// multiplier, rounded down (<https://en.uesp.net/wiki/Skyrim:Crime>). The other
    /// three are flat `CRVA` amounts.
    public func bounty(for event: CrimeEvent) -> Int32 {
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
    public static func stealBounty(of value: Int64, multiplier: Float?) -> Int32 {
        let factor = multiplier ?? defaultStealMultiplier
        guard value > 0, factor.isFinite, factor > 0 else { return 0 }
        return Int32(clamping: Int64((Double(value) * Double(factor)).rounded(.down)))
    }
}
