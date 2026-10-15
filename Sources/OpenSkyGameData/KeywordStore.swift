// Load-order-wide KYWD lookup above RecordIndex. All raw FormIDs are resolved
// relative to the plugin that contained them; callers never carry hardcoded
// vanilla keyword IDs.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedKeyword: Equatable, Sendable {
    public let id: ResolvedFormID
    public let keyword: Keyword
    public let sourcePlugin: String
}

nonisolated public struct KeywordStore: Sendable {
    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedKeyword>

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public init(index: RecordIndex) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["KYWD"],
            decode: { try Keyword(record: $0.record) },
            editorID: \.editorID,
            resolve: { ResolvedKeyword(id: $0, keyword: $1, sourcePlugin: $2) }
        )
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["KYWD"]))
    }

    /// The record type of an indexed form, such as `NPC_` for an actor base.
    public func recordType(of form: ResolvedFormID) -> FourCC? {
        guard case let .record(indexed) = index.lookup(form) else { return nil }
        return indexed.record.type
    }

    /// The `DEST` group of an indexed base form, decoded on each call. Nil when the
    /// record has none or is not indexed.
    public func destructible(of form: ResolvedFormID) -> Destructible? {
        fields(of: form) { $0.destructible() }
    }

    /// The `OBND` box of an indexed base form. Nil when the record has none or is not
    /// indexed.
    public func bounds(of form: ResolvedFormID) -> ObjectBounds? {
        fields(of: form) { $0.bounds() }
    }

    private func fields<Value>(
        of form: ResolvedFormID, _ read: (inout RecordFields) -> Value?
    ) -> Value? {
        guard
            case let .decoded(value, _) = index.decodeIndexed(form, using: { indexed in
                var fields = try RecordFields(
                    record: indexed.record, type: indexed.record.type, localized: indexed.localized
                )
                return read(&fields)
            }) else { return nil }
        return value
    }

    public func keyword(_ id: ResolvedFormID) -> ResolvedKeyword? {
        table.value(id)
    }

    public func keyword(editorID: String) -> ResolvedKeyword? {
        table.value(editorID: editorID)
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index.resolvedID(id, fromPlugin: pluginName)
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedKeyword? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return keyword(resolvedID)
    }

    /// Whether `form` carries `keyword` in its winning KWDA definition. Nil
    /// distinguishes a dangling form or keyword from a real non-membership.
    public func hasKeyword(_ keyword: ResolvedFormID, on form: ResolvedFormID) -> Bool? {
        // The table's id spells the plugin name as the load order does.
        guard let keyword = self.keyword(keyword)?.id else { return nil }
        guard case let .record(indexed) = index.lookup(form) else { return nil }
        guard let fields = try? indexed.record.fields() else { return nil }
        var list = KeywordList()
        for field in fields {
            guard (try? list.decode(field: field)) != nil else { return nil }
        }
        return list.keywords.contains { raw in
            resolvedID(raw, fromPlugin: indexed.sourcePlugin) == keyword
        }
    }

    /// Human-readable reverse view for inspectors. A dangling link remains
    /// visible as its raw FormID instead of disappearing from the dump.
    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.keyword.editorID ?? "[UNRESOLVED] \(id)"
    }
}
