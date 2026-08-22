// Load-order-wide FACT lookup above RecordIndex, in the LocationStore shape:
// the winning record per identity, lookup by identity and by editor id, and
// the joins a consumer would otherwise redo — an actor's memberships resolved
// through the template chain, and a relation resolved to the faction it names.
//
// Nothing here decides hostility, crime response or trade. Those read this
// store and are the rest of milestone M21.

import Foundation

nonisolated struct ResolvedFaction: Equatable {
    let id: ResolvedFormID
    let faction: Faction
    let sourcePlugin: String

    var editorID: String? {
        faction.editorID
    }

    var displayName: String {
        faction.displayName
    }
}

/// One SNAM membership after the store resolved its link: the faction record
/// when the load order carries it, the raw link when it does not, and the rank
/// the actor holds.
nonisolated struct ResolvedFactionMembership: Equatable {
    let rawFaction: FormID
    let faction: ResolvedFaction?
    let rank: Int8

    var isResolved: Bool {
        faction != nil
    }

    var displayName: String {
        faction?.displayName ?? "[UNRESOLVED] \(rawFaction)"
    }
}

nonisolated struct FactionStore {
    private let index: RecordIndex
    private(set) var factions: [ResolvedFormID: ResolvedFaction] = [:]
    private var factionsByEditorID: [String: ResolvedFaction] = [:]
    private var factionsByKey: [ReferenceKey: ResolvedFaction] = [:]

    /// Every faction the load order carries, ordered by identity so a caller
    /// that prints or counts them gets the same answer on every run.
    var sortedFactions: [ResolvedFaction] {
        factions.values.sorted {
            $0.id.plugin.caseInsensitiveCompare($1.id.plugin) == .orderedSame
                ? $0.id.objectID < $1.id.objectID
                : $0.id.plugin.localizedCaseInsensitiveCompare($1.id.plugin) == .orderedAscending
        }
    }

    var vendorFactions: [ResolvedFaction] {
        sortedFactions.filter(\.faction.isVendor)
    }

    var crimeFactions: [ResolvedFaction] {
        sortedFactions.filter(\.faction.tracksCrime)
    }

    init(index: RecordIndex) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            guard index.records[id]?.record.type == "FACT" else { continue }
            add(id)
        }
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(
            plugins: plugins,
            recordTypes: RecordIndex.referenceRecordTypes
        ))
    }

    func faction(_ id: ResolvedFormID) -> ResolvedFaction? {
        factions[canonicalMatch(id)]
    }

    func faction(editorID: String) -> ResolvedFaction? {
        factionsByEditorID[editorID.lowercased()]
    }

    /// The faction one runtime identity names, which is what the faction
    /// runtime looks every stored membership up through (issue #503).
    ///
    /// A separate index rather than a `ResolvedFormID` round trip because
    /// `ReferenceKey` lowercases the plugin name while `ResolvedFormID` keeps
    /// whatever spelling the MAST field used, so the two are not
    /// interchangeable dictionary keys.
    func faction(key: ReferenceKey) -> ResolvedFaction? {
        factionsByKey[key]
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolved) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolved
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFaction? {
        guard let resolved = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return faction(resolved)
    }

    /// A faction link as text: its name when the load order carries the record,
    /// and an explicit unresolved marker when it does not, so a missing record
    /// never reads as a name.
    func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    /// The relations one faction declares, each joined to the record it names.
    /// A relation may name a RACE rather than a FACT, so an unresolved entry is
    /// normal rather than a fault.
    func relations(of resolved: ResolvedFaction) -> [(
        relation: Faction.Relation,
        faction: ResolvedFaction?
    )] {
        resolved.faction.relations.map {
            ($0, resolve($0.faction, fromPlugin: resolved.sourcePlugin))
        }
    }

    /// An actor's memberships after `useFactions` template inheritance, each
    /// joined to the faction record.
    ///
    /// The chain walk is `ActorTemplateResolver`'s, which indexes one plugin by
    /// raw FormID, so `sourcePlugin` names the plugin those FormIDs belong to.
    /// A chain that cannot be walked — a dangling TPLT, a cycle, an empty
    /// leveled list — yields an empty list rather than throwing: a caller
    /// asking who an actor sides with wants an answer it can act on, and the
    /// resolver's own suites cover the failure modes.
    func memberships(
        ofBase base: FormID,
        resolver: ActorTemplateResolver,
        fromPlugin sourcePlugin: String
    ) -> [ResolvedFactionMembership] {
        guard let resolved = try? resolver.resolveFactions(base: base) else { return [] }
        return memberships(resolved.factions.value, fromPlugin: sourcePlugin)
    }

    /// The same join without the chain walk, for a caller that already resolved
    /// the memberships it wants named.
    func memberships(
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
    func rankTitle(
        of membership: ResolvedFactionMembership,
        female: Bool
    ) -> LString? {
        guard let faction = membership.faction, membership.rank >= 0 else { return nil }
        return faction.faction.rankTitle(UInt32(membership.rank), female: female)
    }

    private mutating func add(_ id: ResolvedFormID) {
        guard
            case let .decoded(faction, sourcePlugin) = index.decodeIndexed(
                id,
                using: { try Faction(record: $0.record, localized: $0.localized) }
            )
        else { return }
        let resolved = ResolvedFaction(id: id, faction: faction, sourcePlugin: sourcePlugin)
        factions[id] = resolved
        factionsByKey[ReferenceKey(resolved: id)] = resolved
        if let editorID = faction.editorID {
            factionsByEditorID[editorID.lowercased()] = resolved
        }
    }

    /// Identity is plugin-plus-object-id compared case-insensitively, matching
    /// how `LocationStore` matches a key that was built from a differently
    /// cased plugin name.
    private func canonicalMatch(_ id: ResolvedFormID) -> ResolvedFormID {
        if factions[id] != nil {
            return id
        }
        return factions.keys.first {
            $0.objectID == id.objectID
                && $0.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        } ?? id
    }
}

nonisolated enum FactionStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> FactionStore {
        FactionStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
