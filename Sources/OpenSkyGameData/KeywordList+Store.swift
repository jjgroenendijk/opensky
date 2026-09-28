// Keyword lookups that resolve a record's raw KWDA links through the load order's
// `KeywordStore`. The record shape lives with the parsers in OpenSkyFormats.

import OpenSkyFormats

nonisolated extension KeywordList {
    /// Tests by editor ID after resolving both the requested keyword and this
    /// record's raw KWDA links through the same load order.
    public func contains(
        editorID: String,
        fromPlugin pluginName: String,
        using store: KeywordStore
    ) -> Bool {
        guard let expected = store.keyword(editorID: editorID)?.id else { return false }
        return keywords.contains { store.resolve($0, fromPlugin: pluginName)?.id == expected }
    }

    /// Editor IDs in KWDA order. Dangling links use their raw FormID text so
    /// inspector output remains complete and diagnosable.
    public func displayStrings(
        fromPlugin pluginName: String,
        using store: KeywordStore
    ) -> [String] {
        keywords.map { store.displayString(for: $0, fromPlugin: pluginName) }
    }
}
