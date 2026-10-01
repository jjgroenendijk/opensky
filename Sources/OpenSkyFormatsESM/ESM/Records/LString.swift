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

    public init(field: ESMField, localized: Bool) throws {
        if localized {
            var reader = BinaryReader(field.data)
            self = try .tableID(reader.readUInt32())
        } else {
            var reader = BinaryReader(field.data)
            self = try .inline(reader.readZString())
        }
    }
}
