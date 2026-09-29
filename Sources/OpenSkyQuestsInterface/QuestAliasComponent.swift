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
// Documented in docs/engine/quest-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One filled reference alias: the ALST alias ID and the world reference it
/// resolved to.
///
/// The target is a session-stable `ReferenceKey` rather than a FormID because
/// that is the identity everything downstream addresses — the Papyrus handle
/// map, the condition run-on resolution, the save file — and because a FormID
/// is load-order relative and would be wrong after the plugin list changes.
nonisolated public struct QuestAliasFill: Equatable, Sendable {
    /// ALST/ALLS number the quest's scripts and conditions address the alias by.
    public let aliasID: UInt32
    /// Reference currently in the alias.
    public let reference: ReferenceKey

    public init(aliasID: UInt32, reference: ReferenceKey) {
        self.aliasID = aliasID
        self.reference = reference
    }
}

/// One filled location alias. Locations are base records rather than placed
/// references, so their stable identity is a `ResolvedFormID`, not a
/// `ReferenceKey` exposed through the reference-alias API.
nonisolated public struct QuestLocationAliasFill: Equatable, Sendable {
    public let aliasID: UInt32
    public let location: ResolvedFormID

    public init(aliasID: UInt32, location: ResolvedFormID) {
        self.aliasID = aliasID
        self.location = location
    }
}

/// Why one alias was left unfilled. Every case is a recorded, tallied skip
/// rather than a failure: the quest may still start, and an empty optional
/// alias is a legitimate outcome the Creation Kit documents.
nonisolated public enum QuestAliasSkipKind: Hashable, Sendable {
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

    public var name: String {
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
nonisolated public struct QuestAliasTally: Equatable, Sendable {
    public private(set) var counts: [QuestAliasSkipKind: Int] = [:]

    public var total: Int {
        counts.values.reduce(0, +)
    }

    public var isEmpty: Bool {
        counts.isEmpty
    }

    public var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    public mutating func note(_ kind: QuestAliasSkipKind, count: Int = 1) {
        counts[kind, default: 0] += count
    }

    public mutating func merge(_ other: QuestAliasTally) {
        for (kind, count) in other.counts {
            note(kind, count: count)
        }
    }

    public init(counts: [QuestAliasSkipKind: Int] = [:]) {
        self.counts = counts
    }
}

/// The filled alias table of one quest.
nonisolated public struct QuestAliasState: WorldStateComponent, Sendable {
    /// Filled aliases, sorted by alias ID and unique by it.
    public private(set) var fills: [QuestAliasFill]
    /// Filled ALLS entries, sorted and unique by alias ID like `fills`.
    public private(set) var locationFills: [QuestLocationAliasFill]

    /// A quest whose aliases hold nothing: the state before a start and after
    /// a stop.
    public static let empty = QuestAliasState()

    public static var componentKind: WorldStateComponentKind {
        .questAliases
    }

    /// Normalizes on the way in — duplicates collapse with the last one
    /// winning and the result comes out sorted. This is also the save
    /// decoder's entry point, so a corrupt file degrades into a valid table
    /// rather than failing the whole load.
    public init(
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

    public var isEmpty: Bool {
        fills.isEmpty && locationFills.isEmpty
    }

    public var count: Int {
        fills.count + locationFills.count
    }

    /// Reference filling `aliasID`, or nil when that alias is empty or the
    /// quest defines no such alias.
    public func reference(forAlias aliasID: UInt32) -> ReferenceKey? {
        fills.first { $0.aliasID == aliasID }?.reference
    }

    public func location(forAlias aliasID: UInt32) -> ResolvedFormID? {
        locationFills.first { $0.aliasID == aliasID }?.location
    }

    /// True when `key` already fills some alias of this quest, which is what
    /// the Creation Kit's "will not fill two aliases on the same quest with
    /// the same reference" rule tests.
    public func holds(_ key: ReferenceKey) -> Bool {
        fills.contains { $0.reference == key }
    }

    /// This table with `aliasID` filled by `key`, replacing whatever was there.
    public func filling(_ aliasID: UInt32, with key: ReferenceKey) -> Self {
        QuestAliasState(
            fills: fills.filter { $0.aliasID != aliasID }
                + [QuestAliasFill(aliasID: aliasID, reference: key)],
            locationFills: locationFills.filter { $0.aliasID != aliasID }
        )
    }

    public func fillingLocation(_ aliasID: UInt32, with location: ResolvedFormID) -> Self {
        QuestAliasState(
            fills: fills.filter { $0.aliasID != aliasID },
            locationFills: locationFills.filter { $0.aliasID != aliasID }
                + [QuestLocationAliasFill(aliasID: aliasID, location: location)]
        )
    }
}

nonisolated extension WorldStateComponentKind {
    /// One quest's filled reference aliases. The value type is `QuestAliasState` in
    /// `Sources/OpenSkyEngine/Quests/QuestAliasComponent.swift`, keyed by the same
    /// QUST `ReferenceKey` the `quest` slot uses. It is a slot of its own because
    /// the two have different lifetimes: stage and objective state survives a stop,
    /// while the alias table is cleared by one.
    public static let questAliases = Self(rawValue: "questAliases", order: 7)
}

nonisolated extension WorldStateComponentValue {
    public static func questAliases(_ value: QuestAliasState) -> Self {
        Self(value)
    }
}
