// The references a location lists by location ref type (`LCRT`), which a quest alias
// of the "location alias reference" kind fills from. See docs/formats/locations.md.

public import OpenSkyFormatsESM

nonisolated extension LocationStore {
    /// The references `locationID` lists under `type`, in file order: `LCSR`, then
    /// `ACSR`, without the ones `RCSR` removes.
    public func specialReferences(
        ofType type: ReferenceKey, in locationID: ResolvedFormID
    ) -> [ReferenceKey] {
        guard let resolved = location(locationID) else { return [] }
        let key = { (raw: FormID) in
            resolvedID(raw, fromPlugin: resolved.sourcePlugin).map(ReferenceKey.init(resolved:))
        }
        let place = resolved.location
        let removed = Set(place.removedSpecialReferences.compactMap(key))
        return (place.specialReferences + place.addedSpecialReferences)
            .filter { key($0.type) == type }
            .compactMap { key($0.reference) }
            .filter { !removed.contains($0) }
    }

    /// The references of `type` in `locationID`, then in its child locations, nearest
    /// generation first and FormID order within one. A child is any location whose
    /// PNAM chain reaches `locationID`.
    public func specialReferencesWithChildren(
        ofType type: ReferenceKey, in locationID: ResolvedFormID
    ) -> [ReferenceKey] {
        let children = (descendants[LocationIdentity(locationID)] ?? []).filter { $0 != locationID }
        return ([locationID] + children).flatMap {
            specialReferences(ofType: type, in: $0)
        }
    }
}

/// A location's FormID with the plugin name compared without case, as `PNAM` chains are.
nonisolated struct LocationIdentity: Hashable, Sendable {
    let plugin: String
    let objectID: UInt32

    init(_ id: ResolvedFormID) {
        plugin = id.plugin.lowercased()
        objectID = id.objectID
    }
}

nonisolated extension LocationStore {
    /// Every location under each of its `PNAM` ancestors and under itself, sorted by
    /// generation depth, then plugin and object ID. A cycle is walked once.
    static func descendants(
        in table: ResolvedRecordTable<ResolvedLocation>,
        index: RecordIndex
    ) -> [LocationIdentity: [ResolvedFormID]] {
        let parent = { (id: ResolvedFormID) -> ResolvedFormID? in
            guard let resolved = table.value(id), let raw = resolved.location.parent else {
                return nil
            }
            return index.resolvedID(raw, fromPlugin: resolved.sourcePlugin)
        }
        var found: [LocationIdentity: [(id: ResolvedFormID, depth: Int)]] = [:]
        for id in table.values.keys {
            var chain: [ResolvedFormID] = []
            var current: ResolvedFormID? = id
            var visited: Set<ResolvedFormID> = []
            while let step = current, visited.insert(step).inserted {
                chain.append(step)
                current = parent(step)
            }
            // The depth counts the chain's resolved locations, as `parentChain` does.
            let depth = chain.count(where: { table.value($0) != nil })
            for ancestor in chain {
                found[LocationIdentity(ancestor), default: []].append((id, depth))
            }
        }
        return found.mapValues { members in
            members.sorted { lhs, rhs in
                (lhs.depth, lhs.id.plugin, lhs.id.objectID)
                    < (rhs.depth, rhs.id.plugin, rhs.id.objectID)
            }.map(\.id)
        }
    }
}

nonisolated extension LocationStore {
    /// Every listed reference with its ref types, without the ones `RCSR` removes.
    static func referenceTypes(
        in locations: some Sequence<ResolvedLocation>,
        index: RecordIndex
    ) -> [ReferenceKey: Set<ReferenceKey>] {
        var types: [ReferenceKey: Set<ReferenceKey>] = [:]
        for resolved in locations {
            let key = { (raw: FormID) in
                index.resolvedID(raw, fromPlugin: resolved.sourcePlugin)
                    .map(ReferenceKey.init(resolved:))
            }
            let place = resolved.location
            let removed = Set(place.removedSpecialReferences.compactMap(key))
            for special in place.specialReferences + place.addedSpecialReferences {
                guard
                    let reference = key(special.reference), !removed.contains(reference),
                    let type = key(special.type)
                else { continue }
                types[reference.namingPlayer, default: []].insert(type)
            }
        }
        return types
    }
}
