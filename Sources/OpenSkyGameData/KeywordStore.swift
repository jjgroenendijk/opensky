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

    public var keywords: [ResolvedFormID: ResolvedKeyword] {
        table.values
    }

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
        guard self.keyword(keyword) != nil else { return nil }
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
