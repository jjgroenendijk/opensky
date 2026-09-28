// SCRL record: a spell wrapped in an inventory item. The casting half is the
// same magic-item header, SPIT struct and EFID/EFIT/CTDA effect run SPEL uses;
// the item half is the ground model, the pickup and drop sounds, and the
// 8-byte value + weight DATA every other carryable family writes.
//
// The SPIT words that describe a spell's type and casting style are fixed on a
// scroll: xEdit marks both as internal-edit-only with the single values 0
// ("Scroll") and 3 ("Scroll"), and UESP records cast duration, range and the
// half-cost perk as always zero. All of them decode anyway, so a mod that sets
// them stays inspectable.
//
// Skipped for now: VMAD script attachments and DEST destruction data.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/SCRL"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SCRL
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(SCRL, 'Scroll', ...)`
//     line 10025.
// Layout documented in docs/formats/magic-records.md.

import Foundation

nonisolated struct Scroll {
    let formID: FormID
    let header: MagicItemHeader
    /// DATA — gold value and carry weight.
    let itemValue: ItemValue
    /// SPIT. Nil when the field is absent or too short to decode.
    let data: SpellItemData?
    let effects: [MagicItemEffect]
    let skipped: MagicEffectTally

    var editorID: String? {
        header.fields.editorID
    }

    var name: LString? {
        header.fields.name
    }

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "SCRL" else {
            throw ESMError.malformed("expected SCRL record, got \(record.type)")
        }
        var decoder = MagicItemFields(localized: localized)
        var itemValue = ItemValue.zero
        var skippedItemData = false
        for field in try record.fields() {
            guard field.type == "DATA" else {
                decoder.decode(field)
                continue
            }
            do {
                itemValue = try ItemValue(field: field)
            } catch {
                skippedItemData = true
            }
        }
        formID = FormID(record.formID)
        header = decoder.header
        self.itemValue = itemValue
        data = decoder.data
        effects = decoder.finishEffects()
        var skipped = decoder.skipped
        if skippedItemData {
            skipped.note(.malformedField("DATA"))
        }
        self.skipped = skipped
    }
}
