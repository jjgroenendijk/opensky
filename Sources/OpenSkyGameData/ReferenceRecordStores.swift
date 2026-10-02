// Load-order-wide ECZN, COLL and DOBJ stores above RecordIndex. Record
// identities use ResolvedFormID; every link is resolved relative to the
// plugin definition that authored it.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedEncounterZone: Equatable, Sendable {
    public let id: ResolvedFormID
    public let zone: EncounterZone
    public let sourcePlugin: String
}

nonisolated public struct EncounterZoneStore: Sendable {
    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedEncounterZone>

    public var zones: [ResolvedFormID: ResolvedEncounterZone] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public init(index: RecordIndex) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["ECZN"],
            decode: { try EncounterZone(record: $0.record) },
            editorID: \.editorID,
            resolve: { ResolvedEncounterZone(id: $0, zone: $1, sourcePlugin: $2) }
        )
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["ECZN"]))
    }

    public func zone(_ id: ResolvedFormID) -> ResolvedEncounterZone? {
        table.value(id)
    }

    public func zone(editorID: String) -> ResolvedEncounterZone? {
        table.value(editorID: editorID)
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedEncounterZone? {
        index.resolvedID(id, fromPlugin: pluginName).flatMap { zone($0) }
    }

    public func encounterZone(containing cell: Cell, fromPlugin pluginName: String)
        -> ResolvedEncounterZone?
    {
        guard let raw = cell.encounterZone else { return nil }
        return resolve(raw, fromPlugin: pluginName)
    }

    public func encounterZone(for worldspace: Worldspace, fromPlugin pluginName: String)
        -> ResolvedEncounterZone?
    {
        guard let raw = worldspace.encounterZone else { return nil }
        return resolve(raw, fromPlugin: pluginName)
    }
}

nonisolated public struct ResolvedCollisionLayer: Equatable, Sendable {
    public let id: ResolvedFormID
    public let layer: CollisionLayer
    public let sourcePlugin: String
    public let collidesWith: [ResolvedFormID]
}

nonisolated public struct CollisionLayerStore: Sendable {
    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedCollisionLayer>

    public var layers: [ResolvedFormID: ResolvedCollisionLayer] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public init(index: RecordIndex) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["COLL"],
            decode: { try CollisionLayer(record: $0.record, localized: $0.localized) },
            editorID: \.editorID,
            resolve: { id, layer, sourcePlugin in
                ResolvedCollisionLayer(
                    id: id,
                    layer: layer,
                    sourcePlugin: sourcePlugin,
                    collidesWith: layer.collidesWith.compactMap {
                        index.resolvedID($0, fromPlugin: sourcePlugin)
                    }
                )
            }
        )
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["COLL"]))
    }

    public func layer(_ id: ResolvedFormID) -> ResolvedCollisionLayer? {
        table.value(id)
    }

    public func layer(editorID: String) -> ResolvedCollisionLayer? {
        table.value(editorID: editorID)
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedCollisionLayer? {
        index.resolvedID(id, fromPlugin: pluginName).flatMap { layer($0) }
    }

    public func collisionLayer(for projectile: Projectile, fromPlugin pluginName: String)
        -> ResolvedCollisionLayer?
    {
        guard let raw = projectile.collisionLayer else { return nil }
        return resolve(raw, fromPlugin: pluginName)
    }
}

nonisolated public struct ResolvedDefaultObjects: Equatable, Sendable {
    public let record: DefaultObjects
    public let sourcePlugin: String
}

nonisolated public struct ResolvedDefaultObjectEntry: Equatable, Sendable {
    public let tag: DefaultObjectTag
    public let rawObject: FormID?
    public let object: ResolvedFormID?
    public let sourcePlugin: String
}

nonisolated public struct DefaultObjectStore: Sendable {
    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedDefaultObjects>
    public private(set) var entries: [DefaultObjectTag: ResolvedDefaultObjectEntry] = [:]
    /// Counts every DOBJ definition that failed, because overrides merge by tag.
    public private(set) var skippedRecords = SkippedRecords()

    public init(index: RecordIndex) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["DOBJ"],
            decode: { try DefaultObjects(record: $0.record) },
            editorID: { $0.editorID },
            resolve: { _, record, sourcePlugin in
                ResolvedDefaultObjects(record: record, sourcePlugin: sourcePlugin)
            }
        )
        for definition in index.definitions(of: "DOBJ") {
            merge(definition)
        }
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["DOBJ"]))
    }

    public func defaultObjects(_ id: ResolvedFormID) -> ResolvedDefaultObjects? {
        table.value(id)
    }

    public func defaultObjects(editorID: String) -> ResolvedDefaultObjects? {
        table.value(editorID: editorID)
    }

    public func entry(tag name: String) -> ResolvedDefaultObjectEntry? {
        guard let tag = DefaultObjectTag(name: name) else { return nil }
        return entries[tag]
    }

    public func object(tag name: String) -> ResolvedFormID? {
        entry(tag: name)?.object
    }

    private mutating func merge(_ definition: IndexedRecord) {
        guard
            let decoded = skippedRecords.decode(
                definition.record,
                using: { try DefaultObjects(record: $0) }
            )
        else { return }
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
