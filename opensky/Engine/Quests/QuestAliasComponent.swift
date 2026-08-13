// Filled quest aliases as a world-state component (issue #183, roadmap item
// 13.4): which world reference each of a running quest's reference aliases
// currently stands for.
//
// A component of its own rather than another field on `QuestRuntimeState`,
// keyed by the same QUST `ReferenceKey`, because the two have different
// lifetimes and different save shapes. Stage and objective state survives a
// stop — "stopping a quest is not resetting it" (item 13.2) — while the alias
// table is cleared on stop, since the Creation Kit is explicit that aliases are
// filled when the quest starts and hold nothing before that:
//
//   "Note that the aliases are not actually 'filled' until the quest starts
//   running - what is defined in the Quest Alias tab is how the alias will be
//   filled when the quest starts."
//   (<https://ck.uesp.net/wiki/Alias>)
//
// Keeping them apart also keeps the `QSTS` save chunk byte-identical to what
// item 13.2 wrote: the fills travel in their own additive `QALS` chunk, so a
// build that predates alias resolution still loads a save taken after it.
//
// One invariant, enforced in `init` rather than checked at use sites, for the
// same reason `QuestRuntimeState`'s two are: `fills` is sorted by alias ID and
// holds at most one entry per ID, which is what makes two stores that filled
// the same aliases encode byte-identically.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// One filled reference alias: the ALST alias ID and the world reference it
/// resolved to.
///
/// The target is a session-stable `ReferenceKey` rather than a FormID because
/// that is the identity everything downstream addresses — the Papyrus handle
/// map, the condition run-on resolution, the save file — and because a FormID
/// is load-order relative and would be wrong after the plugin list changes.
nonisolated struct QuestAliasFill: Equatable, Sendable {
    /// ALST/ALLS number the quest's scripts and conditions address the alias by.
    let aliasID: UInt32
    /// Reference currently in the alias.
    let reference: ReferenceKey
}

/// One filled location alias. Locations are base records rather than placed
/// references, so their stable identity is a `ResolvedFormID`, not a
/// `ReferenceKey` exposed through the reference-alias API.
nonisolated struct QuestLocationAliasFill: Equatable, Sendable {
    let aliasID: UInt32
    let location: ResolvedFormID
}

/// Why one alias was left unfilled. Every case is a recorded, tallied skip
/// rather than a failure: the quest may still start, and an empty optional
/// alias is a legitimate outcome the Creation Kit documents.
nonisolated enum QuestAliasSkipKind: Hashable, Sendable {
    /// A fill type OpenSky does not implement yet. Carries the type so the
    /// tally names which ones a corpus actually needs.
    case unsupportedFillType(Quest.Alias.FillType)
    /// A location alias (ALLS) whose fill type still needs condition or
    /// alias-search machinery. Direct ALFL aliases are filled.
    case locationAlias
    /// A specific-location fill was implemented, but its ALFL link did not
    /// name a loaded LCTN.
    case unresolvedLocation
    /// The fill named a reference whose FormID resolves to nothing — a null
    /// FormID, or one no loaded plugin can own. This is the only skip that also
    /// fails a non-optional alias.
    case unresolvedReference
    /// The reference is already in another alias on this quest and the alias
    /// does not allow reuse. Counted, and deliberately not a start failure;
    /// `QuestAliasFiller` states why.
    case reusedInQuest

    var name: String {
        switch self {
        case let .unsupportedFillType(type): "unsupported fill \(type.name)"
        case .locationAlias: "location alias"
        case .unresolvedLocation: "unresolved location"
        case .unresolvedReference: "unresolved reference"
        case .reusedInQuest: "reference reused in quest"
        }
    }
}

/// Reason-tagged count of every alias a fill pass left empty, shaped like
/// `QuestTally` and `ScriptBindingTally`. A census asserts against it; one
/// quest's copy explains why its filled count came out lower than its alias
/// count.
nonisolated struct QuestAliasTally: Equatable, Sendable {
    private(set) var counts: [QuestAliasSkipKind: Int] = [:]

    var total: Int {
        counts.values.reduce(0, +)
    }

    var isEmpty: Bool {
        counts.isEmpty
    }

    var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    mutating func note(_ kind: QuestAliasSkipKind, count: Int = 1) {
        counts[kind, default: 0] += count
    }

    mutating func merge(_ other: QuestAliasTally) {
        for (kind, count) in other.counts {
            note(kind, count: count)
        }
    }
}

/// The filled alias table of one quest.
nonisolated struct QuestAliasState: WorldStateComponent {
    /// Filled aliases, sorted by alias ID and unique by it.
    private(set) var fills: [QuestAliasFill]
    /// Filled ALLS entries, sorted and unique by alias ID like `fills`.
    private(set) var locationFills: [QuestLocationAliasFill]

    /// A quest whose aliases hold nothing: the state before a start and after
    /// a stop.
    static let empty = QuestAliasState()

    static var componentKind: WorldStateComponentKind {
        .questAliases
    }

    var erased: WorldStateComponentValue {
        .questAliases(self)
    }

    /// Normalizes on the way in — duplicates collapse with the last one
    /// winning and the result comes out sorted. This is also the save
    /// decoder's entry point, so a corrupt file degrades into a valid table
    /// rather than failing the whole load.
    init(
        fills: [QuestAliasFill] = [],
        locationFills: [QuestLocationAliasFill] = []
    ) {
        var byID: [UInt32: ReferenceKey] = [:]
        for fill in fills {
            byID[fill.aliasID] = fill.reference
        }
        self.fills = byID.keys.sorted().compactMap { id in
            byID[id].map { QuestAliasFill(aliasID: id, reference: $0) }
        }
        var locationsByID: [UInt32: ResolvedFormID] = [:]
        for fill in locationFills {
            locationsByID[fill.aliasID] = fill.location
        }
        self.locationFills = locationsByID.keys.sorted().compactMap { id in
            locationsByID[id].map { QuestLocationAliasFill(aliasID: id, location: $0) }
        }
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .questAliases(value) = erased else { return nil }
        self = value
    }

    var isEmpty: Bool {
        fills.isEmpty && locationFills.isEmpty
    }

    var count: Int {
        fills.count + locationFills.count
    }

    /// Reference filling `aliasID`, or nil when that alias is empty or the
    /// quest defines no such alias.
    func reference(forAlias aliasID: UInt32) -> ReferenceKey? {
        fills.first { $0.aliasID == aliasID }?.reference
    }

    func location(forAlias aliasID: UInt32) -> ResolvedFormID? {
        locationFills.first { $0.aliasID == aliasID }?.location
    }

    /// True when `key` already fills some alias of this quest, which is what
    /// the Creation Kit's "will not fill two aliases on the same quest with
    /// the same reference" rule tests.
    func holds(_ key: ReferenceKey) -> Bool {
        fills.contains { $0.reference == key }
    }

    /// This table with `aliasID` filled by `key`, replacing whatever was there.
    func filling(_ aliasID: UInt32, with key: ReferenceKey) -> Self {
        QuestAliasState(
            fills: fills.filter { $0.aliasID != aliasID }
                + [QuestAliasFill(aliasID: aliasID, reference: key)],
            locationFills: locationFills.filter { $0.aliasID != aliasID }
        )
    }

    func fillingLocation(_ aliasID: UInt32, with location: ResolvedFormID) -> Self {
        QuestAliasState(
            fills: fills.filter { $0.aliasID != aliasID },
            locationFills: locationFills.filter { $0.aliasID != aliasID }
                + [QuestLocationAliasFill(aliasID: aliasID, location: location)]
        )
    }
}
