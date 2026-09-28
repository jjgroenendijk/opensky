// Load-order-wide LCTN/LCRT lookup and parent traversal above RecordIndex.
// Raw links are resolved relative to the definition that carries them; a
// visited set bounds malformed parent cycles without imposing an arbitrary
// depth limit.

import Foundation

nonisolated struct ResolvedLocation: Equatable {
    let id: ResolvedFormID
    let location: Location
    let sourcePlugin: String
}

nonisolated struct ResolvedLocationRefType: Equatable {
    let id: ResolvedFormID
    let refType: LocationRefType
    let sourcePlugin: String
}

nonisolated struct LocationStore {
    private let index: RecordIndex
    private let keywordStore: KeywordStore
    private(set) var locations: [ResolvedFormID: ResolvedLocation] = [:]
    private(set) var refTypes: [ResolvedFormID: ResolvedLocationRefType] = [:]
    private var locationsByEditorID: [String: ResolvedLocation] = [:]
    private var refTypesByEditorID: [String: ResolvedLocationRefType] = [:]

    init(index: RecordIndex) {
        self.index = index
        keywordStore = KeywordStore(index: index)
        let orderedIDs = index.records.keys.sorted {
            Self.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            switch index.records[id]?.record.type {
            case "LCTN": addLocation(id)
            case "LCRT": addRefType(id)
            default: break
            }
        }
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(
            plugins: plugins,
            recordTypes: RecordIndex.referenceRecordTypes
        ))
    }

    func location(_ id: ResolvedFormID) -> ResolvedLocation? {
        locations[canonicalMatch(id, in: locations)]
    }

    func location(editorID: String) -> ResolvedLocation? {
        locationsByEditorID[editorID.lowercased()]
    }

    func refType(_ id: ResolvedFormID) -> ResolvedLocationRefType? {
        refTypes[canonicalMatch(id, in: refTypes)]
    }

    func refType(editorID: String) -> ResolvedLocationRefType? {
        refTypesByEditorID[editorID.lowercased()]
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolved) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolved
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedLocation? {
        guard let resolved = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return location(resolved)
    }

    /// True when `candidate` is `ancestor` or reaches it through PNAM.
    func isWithin(_ candidate: ResolvedFormID, ancestor: ResolvedFormID) -> Bool {
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
    func hasKeyword(_ keyword: ResolvedFormID, in locationID: ResolvedFormID) -> Bool {
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

    func hasKeyword(editorID: String, in locationID: ResolvedFormID) -> Bool {
        guard let keyword = keywordStore.keyword(editorID: editorID)?.id else { return false }
        return hasKeyword(keyword, in: locationID)
    }

    /// Resolves a KYWD parameter and proves the target record exists.
    func keyword(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard let resolved = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return keywordStore.keyword(resolved)?.id
    }

    /// True when both locations are the same at the immediate level, or reach
    /// the same nearest ancestor carrying `keyword`.
    func sharesLocation(
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
    func isWithinAny(
        _ candidate: ResolvedFormID,
        locations entries: [ResolvedFormID?]
    ) -> Bool? {
        guard location(candidate) != nil else { return nil }
        return entries.compactMap(\.self).contains { isWithin(candidate, ancestor: $0) }
    }

    /// Resolves CELL XLCN through the same load order as LCTN.
    func location(containing cell: Cell, fromPlugin pluginName: String) -> ResolvedLocation? {
        guard let raw = cell.location else { return nil }
        return resolve(raw, fromPlugin: pluginName)
    }

    /// The selected location followed by its parents. A malformed cycle is
    /// represented once and then terminates, matching the containment queries.
    func parentChain(of locationID: ResolvedFormID) -> [ResolvedLocation] {
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

    private mutating func addLocation(_ id: ResolvedFormID) {
        guard
            case let .decoded(location, sourcePlugin) = index.decodeIndexed(
                id,
                using: { try Location(record: $0.record, localized: $0.localized) }
            )
        else { return }
        let resolved = ResolvedLocation(id: id, location: location, sourcePlugin: sourcePlugin)
        locations[id] = resolved
        if let editorID = location.editorID {
            locationsByEditorID[editorID.lowercased()] = resolved
        }
    }

    private mutating func addRefType(_ id: ResolvedFormID) {
        guard
            case let .decoded(refType, sourcePlugin) = index.decode(
                id,
                using: LocationRefType.init(record:)
            )
        else { return }
        let resolved = ResolvedLocationRefType(
            id: id,
            refType: refType,
            sourcePlugin: sourcePlugin
        )
        refTypes[id] = resolved
        if let editorID = refType.editorID {
            refTypesByEditorID[editorID.lowercased()] = resolved
        }
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

    private func canonicalMatch(
        _ id: ResolvedFormID,
        in values: [ResolvedFormID: some Any]
    ) -> ResolvedFormID {
        values.keys.first { sameIdentity($0, id) } ?? id
    }

    private func sameIdentity(_ left: ResolvedFormID, _ right: ResolvedFormID) -> Bool {
        left.objectID == right.objectID
            && left.plugin.caseInsensitiveCompare(right.plugin) == .orderedSame
    }

    private static func precedes(
        _ left: ResolvedFormID,
        _ right: ResolvedFormID,
        index: RecordIndex
    ) -> Bool {
        let leftSource = index.records[left]?.sourcePlugin ?? left.plugin
        let rightSource = index.records[right]?.sourcePlugin ?? right.plugin
        let leftPriority = index.priority(ofPlugin: leftSource)
        let rightPriority = index.priority(ofPlugin: rightSource)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        if left.plugin.caseInsensitiveCompare(right.plugin) != .orderedSame {
            return left.plugin.localizedCaseInsensitiveCompare(right.plugin) == .orderedAscending
        }
        return left.objectID < right.objectID
    }
}

nonisolated enum LocationStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> LocationStore {
        LocationStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
