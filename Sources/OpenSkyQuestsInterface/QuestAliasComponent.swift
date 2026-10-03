// Filled quest aliases as a world-state component: the reference each alias of
// a running quest stands for. Separate from `QuestRuntimeState`, because stage
// state survives a stop and aliases do not (<https://ck.uesp.net/wiki/Alias>).
// Saved in its own `QALS` chunk. `init` keeps `fills` sorted by alias ID, one
// entry per ID. See docs/engine/quest-state.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One filled reference alias: the ALST alias ID and the world reference it
/// resolved to, as a session-stable `ReferenceKey`.
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
nonisolated public enum QuestAliasSkipKind: SkipTallyKind {
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

/// Why a fill pass left each alias empty. One quest's copy explains why its
/// filled count is lower than its alias count.
public typealias QuestAliasTally = SkipTally<QuestAliasSkipKind>

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
    /// `Sources/OpenSkyQuestsInterface/QuestAliasComponent.swift`, keyed by the same
    /// QUST `ReferenceKey` the `quest` slot uses. It is a slot of its own because
    /// the two have different lifetimes: stage and objective state survives a stop,
    /// while the alias table is cleared by one.
    public static let questAliases = Self(
        rawValue: "questAliases", order: 7, affectsCellBuild: false
    )
}
