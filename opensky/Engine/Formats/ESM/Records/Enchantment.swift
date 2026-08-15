// ENCH record: how magic reaches an item. A weapon or a piece of armor names
// one through its EITM link, and the record is identity, the ENIT header, and
// the same EFID/EFIT/CTDA effect run SPEL, SCRL, ALCH and INGR carry.
//
// xEdit spells the whole record as `wbEDID, wbObjectBounds, wbFULL,
// wbStruct(ENIT, ...), wbEffectsReq`, so the three identity fields are decoded
// by name here rather than through `InventoryItemFields`: an ENCH carries none
// of the other carryable-item subrecords, and a decoder that quietly consumed
// them would hide a real surprise from the unread-field tally.
//
// Decode policy follows SPEL: a wrong record type throws, an individual
// malformed field is tallied and the rest of the record still decodes, and a
// truncated ENIT leaves `data == nil` rather than losing the effect list.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/ENCH"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ENCH
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(ENCH, 'Enchantment',
//     ...)` line 5011.
// Layout documented in docs/formats/magic-records.md.

import Foundation

nonisolated struct Enchantment {
    let formID: FormID
    let editorID: String?
    /// FULL — the name shown on an item this enchantment is applied to.
    let name: LString?
    /// OBND. Always written, always zero on a vanilla ENCH.
    let bounds: ObjectBounds?
    /// ENIT. Nil when the field is absent or too short to decode.
    let data: EnchantmentItemData?
    let effects: [MagicItemEffect]
    let skipped: MagicEffectTally

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "ENCH" else {
            throw ESMError.malformed("expected ENCH record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var decoder = EnchantmentFields(localized: localized)
        for field in try record.fields() {
            decoder.decode(field)
        }
        editorID = decoder.editorID
        name = decoder.name
        bounds = decoder.bounds
        data = decoder.data
        effects = decoder.finishEffects()
        skipped = decoder.skipped
    }
}

/// Field accumulator for ENCH: the three identity fields, the ENIT struct, the
/// effect run, and the unread-field tally.
nonisolated private struct EnchantmentFields {
    let localized: Bool
    private(set) var editorID: String?
    private(set) var name: LString?
    private(set) var bounds: ObjectBounds?
    private(set) var data: EnchantmentItemData?
    private(set) var skipped = MagicEffectTally()
    private var effects = MagicItemEffectList()

    init(localized: Bool) {
        self.localized = localized
    }

    mutating func decode(_ field: ESMField) {
        do {
            switch field.type {
            case "EDID":
                var reader = BinaryReader(field.data)
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "OBND":
                bounds = try ObjectBounds(field: field)
            case "ENIT":
                data = try EnchantmentItemData(field: field)
            default:
                if try !effects.decode(field: field) {
                    skipped.note(.unknownField(field.type))
                }
            }
        } catch {
            skipped.note(.malformedField(field.type))
        }
    }

    mutating func finishEffects() -> [MagicItemEffect] {
        effects.finish()
    }
}
