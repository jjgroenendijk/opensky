// Load-order-wide LCTN/LCRT lookup and parent traversal above RecordIndex.
// Raw links are resolved relative to the definition that carries them; a
// visited set bounds malformed parent cycles without imposing an arbitrary
// depth limit.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedLocation: Equatable, Sendable {
    public let id: ResolvedFormID
    public let location: Location
    public let sourcePlugin: String
}

nonisolated public struct LocationStore: Sendable {
    private let index: RecordIndex
    private let keywordStore: KeywordStore
    private let table: ResolvedRecordTable<ResolvedLocation>
    /// Each unique NPC base's placed reference, from the `LCUN` lists. The last
    /// location that names an actor wins. A base the lists miss, such as `Ralof`,
    /// falls back to its one persistent placed actor.
    public let uniqueActorReferences: [ReferenceKey: ReferenceKey]

    public var locations: [ResolvedFormID: ResolvedLocation] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public init(index: RecordIndex, persistentActors: [ReferenceKey: ReferenceKey] = [:]) {
        self.index = index
        keywordStore = KeywordStore(index: index)
        table = ResolvedRecordTable(
            index: index,
            types: ["LCTN"],
            decode: { try Location(record: $0.record, localized: $0.localized) },
            editorID: \.editorID,
            resolve: { ResolvedLocation(id: $0, location: $1, sourcePlugin: $2) }
        )
        uniqueActorReferences = persistentActors.merging(
            Self.uniqueActors(in: table.values.values, index: index)
        ) { _, listed in listed }
    }

    private static func uniqueActors(
        in locations: some Sequence<ResolvedLocation>,
        index: RecordIndex
    ) -> [ReferenceKey: ReferenceKey] {
        var references: [ReferenceKey: ReferenceKey] = [:]
        for location in locations.sorted(by: { $0.id.description < $1.id.description }) {
            for actor in location.location.uniqueActors {
                guard
                    let base = index.resolvedID(actor.actorBase, fromPlugin: location.sourcePlugin),
                    let reference = index.resolvedID(
                        actor.actorReference, fromPlugin: location.sourcePlugin
                    )
                else { continue }
                references[ReferenceKey(resolved: base)] = ReferenceKey(resolved: reference)
            }
        }
        return references
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        let index = RecordIndex(plugins: plugins, recordTypes: RecordIndex.referenceRecordTypes)
        self.init(
            index: index,
            persistentActors: PersistentActorIndex.singleReferences(plugins: plugins, index: index)
        )
    }

    /// The KYWD records over the same index, for conditions that name a keyword.
    public var keywords: KeywordStore {
        keywordStore
    }

    public func location(_ id: ResolvedFormID) -> ResolvedLocation? {
        table.value(id)
    }

    public func location(editorID: String) -> ResolvedLocation? {
        table.value(editorID: editorID)
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index.resolvedID(id, fromPlugin: pluginName)
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedLocation? {
        guard let resolved = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return location(resolved)
    }

    /// True when `candidate` is `ancestor` or reaches it through PNAM.
    public func isWithin(_ candidate: ResolvedFormID, ancestor: ResolvedFormID) -> Bool {
        var current: ResolvedFormID? = candidate
        var visited: Set<ResolvedFormID> = []
        while let id = current, visited.insert(id).inserted {
            if sameIdentity(id, ancestor) {
                return true
            }
            current = parentID(of: id)
        }
        return false
    }

    /// Location keywords are queried over the PNAM chain. Vanilla data uses
    /// parent-only keywords on child places; the same visited-set rule as
    /// `isWithin` makes malformed cycles terminate.
    public func hasKeyword(_ keyword: ResolvedFormID, in locationID: ResolvedFormID) -> Bool {
        var current: ResolvedFormID? = locationID
        var visited: Set<ResolvedFormID> = []
        while
            let id = current,
            visited.insert(id).inserted,
            let resolved = location(id)
        {
            if
                resolved.location.keywords.keywords.contains(where: { raw in
                    resolvedID(raw, fromPlugin: resolved.sourcePlugin).map {
                        sameIdentity($0, keyword)
                    } ?? false
                })
            {
                return true
            }
            current = parentID(of: id)
        }
        return false
    }

    public func hasKeyword(editorID: String, in locationID: ResolvedFormID) -> Bool {
        guard let keyword = keywordStore.keyword(editorID: editorID)?.id else { return false }
        return hasKeyword(keyword, in: locationID)
    }

    /// Resolves a KYWD parameter and proves the target record exists.
    public func keyword(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard let resolved = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return keywordStore.keyword(resolved)?.id
    }

    /// True when both locations are the same at the immediate level, or reach
    /// the same nearest ancestor carrying `keyword`.
    public func sharesLocation(
        _ left: ResolvedFormID,
        _ right: ResolvedFormID,
        at keyword: ResolvedFormID?
    ) -> Bool? {
        guard location(left) != nil, location(right) != nil else { return nil }
        guard let keyword else { return sameIdentity(left, right) }
        guard keywordStore.keyword(keyword) != nil else { return nil }
        guard
            let leftAncestor = firstAncestor(of: left, carrying: keyword),
            let rightAncestor = firstAncestor(of: right, carrying: keyword)
        else { return false }
        return sameIdentity(leftAncestor, rightAncestor)
    }

    /// True when `candidate` or one of its parents is a location leaf in the
    /// already-flattened form list.
    public func isWithinAny(
        _ candidate: ResolvedFormID,
        locations entries: [ResolvedFormID?]
    ) -> Bool? {
        guard location(candidate) != nil else { return nil }
        return entries.compactMap(\.self).contains { isWithin(candidate, ancestor: $0) }
    }

    /// Resolves CELL XLCN through the same load order as LCTN.
    public func location(
        containing cell: Cell,
        fromPlugin pluginName: String
    ) -> ResolvedLocation? {
        guard let raw = cell.location else { return nil }
        return resolve(raw, fromPlugin: pluginName)
    }

    /// The selected location followed by its parents. A malformed cycle is
    /// represented once and then terminates, matching the containment queries.
    public func parentChain(of locationID: ResolvedFormID) -> [ResolvedLocation] {
        var chain: [ResolvedLocation] = []
        var current: ResolvedFormID? = locationID
        var visited: Set<ResolvedFormID> = []
        while
            let id = current,
            visited.insert(id).inserted,
            let resolved = location(id)
        {
            chain.append(resolved)
            current = parentID(of: id)
        }
        return chain
    }

    private func parentID(of id: ResolvedFormID) -> ResolvedFormID? {
        guard
            let resolved = location(id),
            let parent = resolved.location.parent
        else { return nil }
        return resolvedID(parent, fromPlugin: resolved.sourcePlugin)
    }

    private func firstAncestor(
        of locationID: ResolvedFormID,
        carrying keyword: ResolvedFormID
    ) -> ResolvedFormID? {
        var current: ResolvedFormID? = locationID
        var visited: Set<ResolvedFormID> = []
        while let id = current, visited.insert(id).inserted {
            guard let resolved = location(id) else { return nil }
            let matches = resolved.location.keywords.keywords.contains { raw in
                resolvedID(raw, fromPlugin: resolved.sourcePlugin).map {
                    sameIdentity($0, keyword)
                } ?? false
            }
            if matches {
                return id
            }
            current = parentID(of: id)
        }
        return nil
    }

    private func sameIdentity(_ left: ResolvedFormID, _ right: ResolvedFormID) -> Bool {
        left.objectID == right.objectID
            && left.plugin.caseInsensitiveCompare(right.plugin) == .orderedSame
    }
}

nonisolated public enum LocationStoreLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> LocationStore {
        LocationStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
