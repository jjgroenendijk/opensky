// One decoded record with its load-order identity, and the table builder the
// smaller record stores share. A link resolves relative to `sourcePlugin`.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedRecord<Record: Sendable>: Sendable {
    public let id: ResolvedFormID
    public let record: Record
    public let sourcePlugin: String

    public init(id: ResolvedFormID, record: Record, sourcePlugin: String) {
        self.id = id
        self.record = record
        self.sourcePlugin = sourcePlugin
    }
}

extension ResolvedRecord: Equatable where Record: Equatable {}

nonisolated extension ResolvedRecordTable {
    /// A table of one record type whose values are `ResolvedRecord`.
    static func records<Record>(
        index: RecordIndex,
        types: Set<FourCC>,
        decode: (IndexedRecord) throws -> Record,
        editorID: (Record) -> String?
    ) -> ResolvedRecordTable<ResolvedRecord<Record>> where Value == ResolvedRecord<Record> {
        ResolvedRecordTable(
            index: index,
            types: types,
            decode: decode,
            editorID: editorID,
            resolve: { ResolvedRecord(id: $0, record: $1, sourcePlugin: $2) }
        )
    }
}

nonisolated extension RecordIndex {
    /// Nil for a null link or a link to a plugin outside the load order.
    public func link(_ id: FormID?, fromPlugin pluginName: String) -> RecordLink? {
        guard let target = resolvedID(id, fromPlugin: pluginName) else { return nil }
        if case .missing = lookup(target) {
            return RecordLink(target: target, isDangling: true)
        }
        return RecordLink(target: target, isDangling: false)
    }
}

/// A resolved link: the target identity, and whether no indexed record has it.
nonisolated public struct RecordLink: Equatable, Sendable {
    public let target: ResolvedFormID
    public let isDangling: Bool
}

/// One decoded record type across the load order, by identity and editor ID.
nonisolated public struct TypedRecordStore<Record: Sendable>: Sendable {
    public let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedRecord<Record>>

    public init(
        index: RecordIndex,
        types: Set<FourCC>,
        decode: (IndexedRecord) throws -> Record,
        editorID: (Record) -> String?
    ) {
        self.index = index
        table = .records(index: index, types: types, decode: decode, editorID: editorID)
    }

    /// Load order, lowest plugin priority first.
    public var records: [ResolvedRecord<Record>] {
        table.orderedValues
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public func record(_ id: ResolvedFormID) -> ResolvedRecord<Record>? {
        table.value(id)
    }

    public func record(editorID: String) -> ResolvedRecord<Record>? {
        table.value(editorID: editorID)
    }

    public func resolve(_ id: FormID?, fromPlugin pluginName: String) -> ResolvedRecord<Record>? {
        index.resolvedID(id, fromPlugin: pluginName).flatMap { record($0) }
    }

    /// Nil for a null link or a link to a plugin outside the load order.
    public func link(_ id: FormID?, from record: ResolvedRecord<some Any>) -> RecordLink? {
        index.link(id, fromPlugin: record.sourcePlugin)
    }
}

nonisolated extension RecordForest where ID == ResolvedFormID {
    /// Links resolve relative to each record's plugin. An unresolvable link reads as none.
    init<Record>(
        records: [ResolvedRecord<Record>],
        index: RecordIndex,
        parent: (Record) -> FormID?,
        previousSibling: (Record) -> FormID?
    ) {
        self.init(Self.links(
            records: records, index: index, parent: parent, previousSibling: previousSibling
        ))
    }

    static func links<Record>(
        records: [ResolvedRecord<Record>],
        index: RecordIndex,
        parent: (Record) -> FormID?,
        previousSibling: (Record) -> FormID?
    ) -> [Link] {
        records.map {
            Link(
                id: $0.id,
                parent: index.resolvedID(parent($0.record), fromPlugin: $0.sourcePlugin),
                previousSibling: index.resolvedID(
                    previousSibling($0.record),
                    fromPlugin: $0.sourcePlugin
                )
            )
        }
    }
}
