// Load-order-wide ECZN, COLL and DOBJ stores above RecordIndex. Record
// identities use ResolvedFormID; every link is resolved relative to the
// plugin definition that authored it.

import Foundation

nonisolated struct ResolvedEncounterZone: Equatable {
    let id: ResolvedFormID
    let zone: EncounterZone
    let sourcePlugin: String
    let owner: ResolvedFormID?
    let location: ResolvedFormID?
}

nonisolated struct EncounterZoneStore {
    private let index: RecordIndex
    private(set) var zones: [ResolvedFormID: ResolvedEncounterZone] = [:]
    private var zonesByEditorID: [String: ResolvedEncounterZone] = [:]

    init(index: RecordIndex) {
        self.index = index
        for id in index.orderedRecordIDs(of: "ECZN") {
            add(id)
        }
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["ECZN"]))
    }

    func zone(_ id: ResolvedFormID) -> ResolvedEncounterZone? {
        zones[index.canonicalMatch(id, in: zones)]
    }

    func zone(editorID: String) -> ResolvedEncounterZone? {
        zonesByEditorID[editorID.lowercased()]
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedEncounterZone? {
        guard case let .resolved(resolved) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return zone(resolved)
    }

    func encounterZone(containing cell: Cell, fromPlugin pluginName: String)
        -> ResolvedEncounterZone?
    {
        guard let raw = cell.encounterZone else { return nil }
        return resolve(raw, fromPlugin: pluginName)
    }

    func encounterZone(for worldspace: Worldspace, fromPlugin pluginName: String)
        -> ResolvedEncounterZone?
    {
        guard let raw = worldspace.encounterZone else { return nil }
        return resolve(raw, fromPlugin: pluginName)
    }

    private mutating func add(_ id: ResolvedFormID) {
        guard
            case let .decoded(zone, sourcePlugin) = index.decode(
                id,
                using: EncounterZone.init(record:)
            )
        else { return }
        let resolved = ResolvedEncounterZone(
            id: id,
            zone: zone,
            sourcePlugin: sourcePlugin,
            owner: index.resolvedID(zone.owner, fromPlugin: sourcePlugin),
            location: index.resolvedID(zone.location, fromPlugin: sourcePlugin)
        )
        zones[id] = resolved
        if let editorID = zone.editorID {
            zonesByEditorID[editorID.lowercased()] = resolved
        }
    }
}

nonisolated struct ResolvedCollisionLayer: Equatable {
    let id: ResolvedFormID
    let layer: CollisionLayer
    let sourcePlugin: String
    let collidesWith: [ResolvedFormID]
}

nonisolated struct CollisionLayerStore {
    private let index: RecordIndex
    private(set) var layers: [ResolvedFormID: ResolvedCollisionLayer] = [:]
    private var layersByEditorID: [String: ResolvedCollisionLayer] = [:]

    init(index: RecordIndex) {
        self.index = index
        for id in index.orderedRecordIDs(of: "COLL") {
            add(id)
        }
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["COLL"]))
    }

    func layer(_ id: ResolvedFormID) -> ResolvedCollisionLayer? {
        layers[index.canonicalMatch(id, in: layers)]
    }

    func layer(editorID: String) -> ResolvedCollisionLayer? {
        layersByEditorID[editorID.lowercased()]
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedCollisionLayer? {
        guard case let .resolved(resolved) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return layer(resolved)
    }

    func collisionLayer(for projectile: Projectile, fromPlugin pluginName: String)
        -> ResolvedCollisionLayer?
    {
        guard let raw = projectile.collisionLayer else { return nil }
        return resolve(raw, fromPlugin: pluginName)
    }

    private mutating func add(_ id: ResolvedFormID) {
        guard
            case let .decoded(layer, sourcePlugin) = index.decodeIndexed(
                id,
                using: { try CollisionLayer(record: $0.record, localized: $0.localized) }
            )
        else { return }
        let links = layer.collidesWith.compactMap {
            index.resolvedID($0, fromPlugin: sourcePlugin)
        }
        let resolved = ResolvedCollisionLayer(
            id: id,
            layer: layer,
            sourcePlugin: sourcePlugin,
            collidesWith: links
        )
        layers[id] = resolved
        if let editorID = layer.editorID {
            layersByEditorID[editorID.lowercased()] = resolved
        }
    }
}

nonisolated struct ResolvedDefaultObjects: Equatable {
    let id: ResolvedFormID
    let record: DefaultObjects
    let sourcePlugin: String
}

nonisolated struct ResolvedDefaultObjectEntry: Equatable {
    let tag: DefaultObjectTag
    let rawObject: FormID?
    let object: ResolvedFormID?
    let sourcePlugin: String
}

nonisolated struct DefaultObjectStore {
    private let index: RecordIndex
    private(set) var records: [ResolvedFormID: ResolvedDefaultObjects] = [:]
    private(set) var entries: [DefaultObjectTag: ResolvedDefaultObjectEntry] = [:]
    private var recordsByEditorID: [String: ResolvedDefaultObjects] = [:]

    init(index: RecordIndex) {
        self.index = index
        for id in index.orderedRecordIDs(of: "DOBJ") {
            addRecord(id)
        }
        for definition in index.definitions(of: "DOBJ") {
            merge(definition)
        }
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["DOBJ"]))
    }

    func defaultObjects(_ id: ResolvedFormID) -> ResolvedDefaultObjects? {
        records[index.canonicalMatch(id, in: records)]
    }

    func defaultObjects(editorID: String) -> ResolvedDefaultObjects? {
        recordsByEditorID[editorID.lowercased()]
    }

    func entry(tag name: String) -> ResolvedDefaultObjectEntry? {
        guard let tag = DefaultObjectTag(name: name) else { return nil }
        return entries[tag]
    }

    func object(tag name: String) -> ResolvedFormID? {
        entry(tag: name)?.object
    }

    private mutating func addRecord(_ id: ResolvedFormID) {
        guard
            case let .decoded(record, sourcePlugin) = index.decode(
                id,
                using: DefaultObjects.init(record:)
            )
        else { return }
        let resolved = ResolvedDefaultObjects(
            id: id,
            record: record,
            sourcePlugin: sourcePlugin
        )
        records[id] = resolved
        recordsByEditorID[record.editorID.lowercased()] = resolved
    }

    private mutating func merge(_ definition: IndexedRecord) {
        guard let decoded = try? DefaultObjects(record: definition.record) else { return }
        for entry in decoded.entries {
            entries[entry.tag] = ResolvedDefaultObjectEntry(
                tag: entry.tag,
                rawObject: entry.object,
                object: index.resolvedID(entry.object, fromPlugin: definition.sourcePlugin),
                sourcePlugin: definition.sourcePlugin
            )
        }
    }
}

nonisolated extension RecordIndex {
    fileprivate func resolvedID(_ id: FormID?, fromPlugin pluginName: String)
        -> ResolvedFormID?
    {
        guard
            let id,
            case let .resolved(resolved) = resolve(id, fromPlugin: pluginName)
        else { return nil }
        return resolved
    }

    fileprivate func orderedRecordIDs(of type: FourCC) -> [ResolvedFormID] {
        records.keys
            .filter { records[$0]?.record.type == type }
            .sorted { left, right in
                let leftSource = records[left]?.sourcePlugin ?? left.plugin
                let rightSource = records[right]?.sourcePlugin ?? right.plugin
                let leftPriority = priority(ofPlugin: leftSource)
                let rightPriority = priority(ofPlugin: rightSource)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                if left.plugin.caseInsensitiveCompare(right.plugin) != .orderedSame {
                    return left.plugin.localizedCaseInsensitiveCompare(right.plugin)
                        == .orderedAscending
                }
                return left.objectID < right.objectID
            }
    }

    fileprivate func canonicalMatch(
        _ id: ResolvedFormID,
        in values: [ResolvedFormID: some Any]
    ) -> ResolvedFormID {
        values.keys.first {
            $0.objectID == id.objectID
                && $0.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        } ?? id
    }
}

nonisolated enum ReferenceRecordStoreLoader {
    static func encounterZones(
        root: GameDataRoot,
        baseFile: ESMFile? = nil
    ) -> EncounterZoneStore {
        EncounterZoneStore(index: RecordIndexLoader.load(root: root, baseFile: baseFile))
    }

    static func collisionLayers(
        root: GameDataRoot,
        baseFile: ESMFile? = nil
    ) -> CollisionLayerStore {
        CollisionLayerStore(index: RecordIndexLoader.load(root: root, baseFile: baseFile))
    }

    static func defaultObjects(
        root: GameDataRoot,
        baseFile: ESMFile? = nil
    ) -> DefaultObjectStore {
        DefaultObjectStore(index: RecordIndexLoader.load(root: root, baseFile: baseFile))
    }
}
