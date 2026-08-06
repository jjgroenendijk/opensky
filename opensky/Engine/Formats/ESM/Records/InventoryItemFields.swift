// The subrecord set every carryable base record shares, decoded once.
//
// MISC, BOOK, ALCH, INGR, WEAP, AMMO and ARMO all open with the same run of
// fields — editor id, display name, ground model, object bounds, keyword
// array, inventory/message icon paths, and the pickup/drop sound links — and
// all but ALCH close with an 8-byte DATA of gold value plus weight. Rather
// than repeat that switch in seven decoders, each record composes
// `InventoryItemFields` and adds only its type-specific cases.
//
// `ItemValue` is separate from the accumulator because ALCH breaks the
// pattern: its DATA is a bare float weight and its gold value lives in ENIT,
// so the ingestible decoder fills the same engine-level value/weight pair from
// two different fields.
//
// References:
//   UESP "Skyrim Mod:Mod File Format" subpages /MISC, /BOOK, /ALCH, /INGR,
//   /WEAP, /AMMO, /ARMO — the shared rows (EDID, FULL, MODL, OBND, KSIZ/KWDA,
//   ICON, MICO, YNAM, ZNAM, DATA) are identical across all seven, e.g.
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MISC
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas: MISC (line 8303), KEYM (7942)
//   and INGR (7909) all spell the 8-byte DATA as int32 Value + float Weight.
// Layout documented in docs/formats/records.md.

import Foundation

/// The 8-byte DATA struct shared by MISC, INGR, KEYM and ARMO: gold value then
/// weight. xEdit types the value int32 (MISC, INGR) or uint32 (ARMO, AMMO);
/// int32 is the wider of the two on disk, so it is what the engine carries.
nonisolated struct ItemValue: Equatable {
    /// Gold value before enchantment adjustments.
    let value: Int32
    /// Carry weight.
    let weight: Float

    static let zero = ItemValue(value: 0, weight: 0)

    init(value: Int32, weight: Float) {
        self.value = value
        self.weight = weight
    }

    /// Decodes an 8-byte value+weight DATA. Shorter payloads throw: a wrong
    /// gold value or weight is worse than a skipped record, and every vanilla
    /// record writes the full struct.
    init(field: ESMField) throws {
        guard field.data.count >= 8 else {
            throw ESMError.malformed(
                "\(field.type) has \(field.data.count) bytes, expected 8 (value + weight)"
            )
        }
        var reader = BinaryReader(field.data)
        value = try Int32(bitPattern: reader.readUInt32())
        weight = try reader.readFloat32()
    }
}

/// Mutable accumulator for the shared carryable-item fields. Records call
/// `decode(field:localized:)` first and handle only what it declines, which
/// keeps each record's own switch inside the strict-lint complexity cap.
nonisolated struct InventoryItemFields {
    var editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    var name: LString?
    /// MODL — ground/world model path relative to Data/.
    var modelPath: String?
    var bounds: ObjectBounds?
    var keywords = KeywordList()
    /// ICON — inventory image path relative to Data/.
    var iconPath: String?
    /// MICO — message-menu image path relative to Data/.
    var messageIconPath: String?
    /// YNAM — SNDR played on pickup.
    var pickupSound: FormID?
    /// ZNAM — SNDR played on drop.
    var dropSound: FormID?

    init() {}

    /// Decodes `field` when it is one of the shared subrecords and reports
    /// whether it was consumed. DATA is deliberately *not* handled here: its
    /// layout is type-specific (8 bytes on MISC/INGR, 4 on ALCH, 10 on WEAP,
    /// 16 on BOOK, 16 or 20 on AMMO), so each record owns that case.
    mutating func decode(field: ESMField, localized: Bool) throws -> Bool {
        if try keywords.decode(field: field) {
            return true
        }
        var reader = BinaryReader(field.data)
        switch field.type {
        case "EDID":
            editorID = try reader.readZString()
        case "FULL":
            name = try LString(field: field, localized: localized)
        case "MODL":
            modelPath = try reader.readZString()
        case "OBND":
            bounds = try ObjectBounds(field: field)
        case "ICON":
            iconPath = try reader.readZString()
        case "MICO":
            messageIconPath = try reader.readZString()
        case "YNAM":
            pickupSound = try Self.optionalFormID(field)
        case "ZNAM":
            dropSound = try Self.optionalFormID(field)
        default:
            return false
        }
        return true
    }

    /// Reads a 4-byte FormID link, mapping the null sentinel and any
    /// unexpected payload length onto nil.
    static func optionalFormID(_ field: ESMField) throws -> FormID? {
        guard field.data.count >= 4 else { return nil }
        var reader = BinaryReader(field.data)
        let formID = try FormID(reader.readUInt32())
        return formID.isNull ? nil : formID
    }
}
