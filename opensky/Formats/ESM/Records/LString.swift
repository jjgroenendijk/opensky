// "lstring" display text: plugins with the TES4 localized flag store a uint32
// string ID (resolved against per-language tables, see
// docs/formats/strings.md); non-localized plugins store an inline zstring in
// the same field. Which one a field holds is a property of the whole plugin,
// so decoding needs the TES4 flag passed in.
//
// Reference: UESP "Skyrim Mod:Mod File Format" — Data types (lstring).
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format

import Foundation

nonisolated enum LString: Equatable {
    case inline(String)
    /// ID into the owning plugin's string tables; which table (.strings /
    /// .dlstrings / .ilstrings) depends on the field, not the ID.
    case tableID(UInt32)

    init(field: ESMField, localized: Bool) throws {
        if localized {
            var reader = BinaryReader(field.data)
            self = try .tableID(reader.readUInt32())
        } else {
            var reader = BinaryReader(field.data)
            let bytes = try reader.readZStringData()
            guard let text = GameText.decode(bytes) else {
                throw ESMError.malformed("\(field.type) holds undecodable text")
            }
            self = .inline(text)
        }
    }
}
