// Finds a record's FULL name in its plugin's string table. A localized plugin such as
// Skyrim.esm stores only a string ID in the record. See docs/formats/strings.md.

import OpenSkyFormatsESM

nonisolated public struct RecordNameLookup: Sendable {
    public let strings: LocalizedStrings?

    /// No tables: a table ID stays unresolved, and the stores fall back to the editor ID.
    public static let none = Self(strings: nil)

    public init(strings: LocalizedStrings?) {
        self.strings = strings
    }

    /// The text of `name` from the tables of `plugin`, the plugin that wrote the record.
    /// Nil without tables, or when the table lacks the ID.
    func text(_ name: LString?, plugin: String) -> String? {
        switch name {
        case nil: nil
        case let .inline(value): value
        case .tableID, .pluginTableID: strings?.scoped(to: plugin).resolve(name)
        }
    }
}
