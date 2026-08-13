// KSIZ + KWDA, the keyword array carried by nearly every object record.
// KSIZ is a uint32 count and KWDA is a packed array of that many KYWD FormIDs
// in the following subrecord. The pair is shared by MISC, BOOK, ALCH, INGR,
// WEAP, AMMO and ARMO, so it decodes once here rather than seven times.
//
// Decode policy: KSIZ is advisory. The real length is `KWDA.count / 4`, so a
// KSIZ that disagrees with the payload is recorded (`declaredCount`) but never
// used to size the read — a mod that writes a stale count must not make the
// engine read past the field or drop keywords that are really there.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/WEAP" (KSIZ keywordCount, KWDA
//   formID[KSIZ.keywordCount]):
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WEAP
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbKeywords`, which models KWDA
//   as an array sized from KSIZ.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct KeywordList: Equatable {
    /// KWDA entries in file order. Empty when the record carries no keywords.
    private(set) var keywords: [FormID] = []
    /// KSIZ as written, kept for diagnostics only. Nil when KSIZ is absent —
    /// which is legal, since a KWDA can appear without one in modded data.
    private(set) var declaredCount: UInt32?

    init() {}

    /// True when KSIZ is present and disagrees with the decoded KWDA length.
    var countMismatch: Bool {
        guard let declaredCount else { return false }
        return Int(declaredCount) != keywords.count
    }

    /// Decodes `field` when it is KSIZ or KWDA and reports whether it was
    /// consumed, so a record's field switch can fall through to its own cases.
    mutating func decode(field: ESMField) throws -> Bool {
        switch field.type {
        case "KSIZ":
            guard field.data.count >= 4 else { return true }
            var reader = BinaryReader(field.data)
            declaredCount = try reader.readUInt32()
        case "KWDA":
            var reader = BinaryReader(field.data)
            // Trailing bytes past the last whole FormID are ignored rather
            // than throwing: the keyword list is advisory data, and losing one
            // malformed tail entry costs less than dropping the record.
            for _ in 0 ..< (field.data.count / 4) {
                try keywords.append(FormID(reader.readUInt32()))
            }
        default:
            return false
        }
        return true
    }

    func contains(_ keyword: FormID) -> Bool {
        keywords.contains(keyword)
    }

    /// Tests by editor ID after resolving both the requested keyword and this
    /// record's raw KWDA links through the same load order.
    func contains(
        editorID: String,
        fromPlugin pluginName: String,
        using store: KeywordStore
    ) -> Bool {
        guard let expected = store.keyword(editorID: editorID)?.id else { return false }
        return keywords.contains { store.resolve($0, fromPlugin: pluginName)?.id == expected }
    }

    /// Editor IDs in KWDA order. Dangling links use their raw FormID text so
    /// inspector output remains complete and diagnosable.
    func displayStrings(fromPlugin pluginName: String, using store: KeywordStore) -> [String] {
        keywords.map { store.displayString(for: $0, fromPlugin: pluginName) }
    }
}
