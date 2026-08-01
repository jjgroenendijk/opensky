// MISC record decoded into engine types: the plain carryable object — gems,
// ingots, tools, gold, clutter. Nothing type-specific beyond the shared
// carryable-item fields plus the 8-byte value/weight DATA, which is exactly
// why it is the simplest of the seven inventory families.
//
// Skipped: VMAD (no MISC script consumer yet), DEST destruction data.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/MISC"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MISC
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(MISC, ...)` line 8303
//     — DATA is int32 Value + float Weight.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct MiscItem {
    let formID: FormID
    /// Shared carryable-item subrecords: EDID, FULL, MODL, OBND, keywords,
    /// icons, pickup/drop sounds.
    let fields: InventoryItemFields
    /// DATA — gold value and carry weight.
    let itemValue: ItemValue

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "MISC" else {
            throw ESMError.malformed("expected MISC record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = InventoryItemFields()
        var itemValue = ItemValue.zero
        for field in try record.fields() {
            if try fields.decode(field: field, localized: localized) {
                continue
            }
            if field.type == "DATA" {
                itemValue = try ItemValue(field: field)
            }
        }
        self.fields = fields
        self.itemValue = itemValue
    }
}
