// "lstring" text: a localized plugin stores a uint32 string ID, any other
// plugin an inline zstring. The TES4 localized flag decides, so it is passed
// in. See docs/formats/strings.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum LString: Equatable, Sendable {
    case inline(String)
    /// ID into the owning plugin's string tables; which table (.strings /
    /// .dlstrings / .ilstrings) depends on the field, not the ID.
    case tableID(UInt32)
    /// ID into the string tables of `plugin`, a plugin after the first in the
    /// load order (`RecordDecodeScope`).
    case pluginTableID(UInt32, plugin: String)

    public init(field: ESMField, localized: Bool) throws {
        if localized {
            var reader = BinaryReader(field.data)
            let id = try reader.readUInt32()
            self = RecordDecodeScope.stringPlugin
                .map { .pluginTableID(id, plugin: $0) } ?? .tableID(id)
        } else {
            var reader = BinaryReader(field.data)
            self = try .inline(reader.readZString())
        }
    }
}

nonisolated extension LString {
    /// The string-table ID, whichever plugin's tables hold it; nil for inline text.
    public var tableIDValue: UInt32? {
        switch self {
        case .inline: nil
        case let .tableID(id), let .pluginTableID(id, _): id
        }
    }
}
