// Load-order-wide KYWD lookup above RecordIndex. All raw FormIDs are resolved
// relative to the plugin that contained them; callers never carry hardcoded
// vanilla keyword IDs.

import Foundation

nonisolated struct ResolvedKeyword: Equatable {
    let id: ResolvedFormID
    let keyword: Keyword
    let sourcePlugin: String
}

nonisolated struct KeywordStore {
    private let index: RecordIndex
    private(set) var keywords: [ResolvedFormID: ResolvedKeyword] = [:]
    private var keywordsByEditorID: [String: ResolvedKeyword] = [:]

    init(index: RecordIndex) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            Self.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            guard index.records[id]?.record.type == "KYWD" else { continue }
            guard
                case let .decoded(keyword, sourcePlugin) = index.decode(
                    id,
                    using: Keyword.init(record:)
                ) else { continue }
            let resolved = ResolvedKeyword(
                id: id,
                keyword: keyword,
                sourcePlugin: sourcePlugin
            )
            keywords[id] = resolved
            if let editorID = keyword.editorID {
                keywordsByEditorID[editorID.lowercased()] = resolved
            }
        }
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["KYWD"]))
    }

    func keyword(_ id: ResolvedFormID) -> ResolvedKeyword? {
        keywords[id] ?? keywords.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    func keyword(editorID: String) -> ResolvedKeyword? {
        keywordsByEditorID[editorID.lowercased()]
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedKeyword? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return keyword(resolvedID)
    }

    /// Whether `form` carries `keyword` in its winning KWDA definition. Nil
    /// distinguishes a dangling form or keyword from a real non-membership.
    func hasKeyword(_ keyword: ResolvedFormID, on form: ResolvedFormID) -> Bool? {
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
    func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.keyword.editorID ?? "[UNRESOLVED] \(id)"
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

nonisolated enum KeywordStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> KeywordStore {
        KeywordStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
