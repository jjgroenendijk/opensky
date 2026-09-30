// Load-order-wide FACT lookup above RecordIndex, plus the joins consumers
// would otherwise redo: memberships and relations resolved to factions.
// Hostility, crime and trade rules read this store; none live here.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedFaction: Equatable, Sendable {
    public let id: ResolvedFormID
    public let faction: Faction
    public let sourcePlugin: String

    public var editorID: String? {
        faction.editorID
    }

    public var displayName: String {
        faction.displayName
    }
}

/// One SNAM membership after the store resolved its link: the faction record
/// when the load order carries it, the raw link when it does not, and the rank
/// the actor holds.
nonisolated public struct ResolvedFactionMembership: Equatable, Sendable {
    public let rawFaction: FormID
    public let faction: ResolvedFaction?
    public let rank: Int8

    public var isResolved: Bool {
        faction != nil
    }

    public var displayName: String {
        faction?.displayName ?? "[UNRESOLVED] \(rawFaction)"
    }
}

nonisolated public struct FactionStore: Sendable {
    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedFaction>
    private let factionsByKey: [ReferenceKey: ResolvedFaction]

    public var factions: [ResolvedFormID: ResolvedFaction] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    /// The faction the `GFAC` default object names, which tells a guard from
    /// other crime-faction members. Vanilla names `IsGuardFaction`. Nil without
    /// a `GFAC` entry, where nobody is a guard.
    public private(set) var guardFaction: ResolvedFaction?

    /// Every faction the load order carries, ordered by identity so a caller
    /// that prints or counts them gets the same answer on every run.
    public var sortedFactions: [ResolvedFaction] {
        factions.values.sorted {
            $0.id.plugin.caseInsensitiveCompare($1.id.plugin) == .orderedSame
                ? $0.id.objectID < $1.id.objectID
                : $0.id.plugin.localizedCaseInsensitiveCompare($1.id.plugin) == .orderedAscending
        }
    }

    public var vendorFactions: [ResolvedFaction] {
        sortedFactions.filter(\.faction.isVendor)
    }

    public var crimeFactions: [ResolvedFaction] {
        sortedFactions.filter(\.faction.tracksCrime)
    }

    public init(index: RecordIndex) {
        self.index = index
        let table = ResolvedRecordTable(
            index: index,
            types: ["FACT"],
            decode: { try Faction(record: $0.record, localized: $0.localized) },
            editorID: \.editorID,
            resolve: { ResolvedFaction(id: $0, faction: $1, sourcePlugin: $2) }
        )
        self.table = table
        factionsByKey = Dictionary(
            table.values.values.map { (ReferenceKey(resolved: $0.id), $0) },
            uniquingKeysWith: { _, later in later }
        )
        guardFaction = DefaultObjectStore(index: index)
            .object(tag: "GFAC")
            .flatMap { table.value($0) }
    }

    /// The guard faction as the runtime identity memberships are keyed by.
    public var guardFactionKey: ReferenceKey? {
        guardFaction.map { ReferenceKey(resolved: $0.id) }
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(
            plugins: plugins,
            recordTypes: RecordIndex.referenceRecordTypes
        ))
    }

    public func faction(_ id: ResolvedFormID) -> ResolvedFaction? {
        table.value(id)
    }

    public func faction(editorID: String) -> ResolvedFaction? {
        table.value(editorID: editorID)
    }

    /// The faction one runtime identity names. A separate index, because
    /// `ReferenceKey` lowercases the plugin name and `ResolvedFormID` does not.
    public func faction(key: ReferenceKey) -> ResolvedFaction? {
        factionsByKey[key]
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index.resolvedID(id, fromPlugin: pluginName)
    }

    /// One of `faction`'s own links, such as `STOL` or `JAIL`, as a runtime
    /// identity, resolved through the plugin that defined the faction.
    public func linkKey(_ link: FormID?, of faction: ResolvedFaction) -> ReferenceKey? {
        guard let link, let id = resolvedID(link, fromPlugin: faction.sourcePlugin) else {
            return nil
        }
        return ReferenceKey(resolved: id)
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFaction? {
        guard let resolved = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return faction(resolved)
    }

    /// A faction link as text: its name when the load order carries the record,
    /// and an explicit unresolved marker when it does not, so a missing record
    /// never reads as a name.
    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    /// The relations one faction declares, each joined to the record it names.
    /// A relation may name a RACE rather than a FACT, so an unresolved entry is
    /// normal rather than a fault.
    public func relations(of resolved: ResolvedFaction) -> [(
        relation: Faction.Relation,
        faction: ResolvedFaction?
    )] {
        resolved.faction.relations.map {
            ($0, resolve($0.faction, fromPlugin: resolved.sourcePlugin))
        }
    }

    /// The same join without the chain walk, for a caller that already resolved
    /// the memberships it wants named.
    public func memberships(
        _ memberships: [ActorBase.FactionMembership],
        fromPlugin sourcePlugin: String
    ) -> [ResolvedFactionMembership] {
        memberships.map {
            ResolvedFactionMembership(
                rawFaction: $0.faction,
                faction: resolve($0.faction, fromPlugin: sourcePlugin),
                rank: $0.rank
            )
        }
    }

    /// The rank title one membership shows, or nil when the faction does not
    /// resolve or names no title for that rank.
    public func rankTitle(
        of membership: ResolvedFactionMembership,
        female: Bool
    ) -> LString? {
        guard let faction = membership.faction, membership.rank >= 0 else { return nil }
        return faction.faction.rankTitle(UInt32(membership.rank), female: female)
    }
}

nonisolated public enum FactionStoreLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> FactionStore {
        FactionStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
