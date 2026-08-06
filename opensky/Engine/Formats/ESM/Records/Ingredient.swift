// INGR record decoded into engine types: alchemy ingredients. Same MagicItem
// shape as ALCH — an effect list plus an ENIT header — but INGR keeps the
// ordinary 8-byte value/weight DATA and its ENIT is only 8 bytes.
//
// ENIT is an 8-byte struct:
//   00 int32   ingredient value used by auto-calc (every vanilla ingredient
//              auto-calculates, so this is not the gold value; that is DATA)
//   04 uint32  flags — 0x001 no auto-calc, 0x002 food, 0x100 references
//              persist
//
// Effects (EFID/EFIT/CTDA runs) decode as links only — see MagicItemEffect.
// Vanilla ingredients carry exactly four, and which of them the player has
// discovered is save state, not record data.
//
// Skipped: VMAD (used only by Briarhearts in the vanilla files), DEST, ETYP.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/INGR"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INGR
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(INGR, ...)` line 7909
//     — int32 Value + float Weight DATA, then the 8-byte ENIT above.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct Ingredient {
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt32

        /// Ingredient value is authored rather than summed from the effects.
        static let noAutoCalc = Flags(rawValue: 0x0000_0001)
        static let food = Flags(rawValue: 0x0000_0002)
        static let referencesPersist = Flags(rawValue: 0x0000_0100)
    }

    let formID: FormID
    let fields: InventoryItemFields
    /// DATA — gold value and carry weight.
    let itemValue: ItemValue
    /// ENIT value word. Distinct from `itemValue.value`: this one feeds the
    /// auto-calc cost formula, the DATA one is the price.
    let autoCalcValue: Int32
    let flags: Flags
    let effects: [MagicItemEffect]

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "INGR" else {
            throw ESMError.malformed("expected INGR record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = InventoryItemFields()
        var effectList = MagicItemEffectList()
        var itemValue = ItemValue.zero
        var autoCalcValue: Int32 = 0
        var flags = Flags()
        for field in try record.fields() {
            if try fields.decode(field: field, localized: localized) {
                continue
            }
            if try effectList.decode(field: field) {
                continue
            }
            switch field.type {
            case "DATA":
                itemValue = try ItemValue(field: field)
            case "ENIT":
                guard field.data.count >= 8 else { break }
                var reader = BinaryReader(field.data)
                autoCalcValue = try Int32(bitPattern: reader.readUInt32())
                flags = try Flags(rawValue: reader.readUInt32())
            default:
                break
            }
        }
        self.fields = fields
        self.itemValue = itemValue
        self.autoCalcValue = autoCalcValue
        self.flags = flags
        effects = effectList.finish()
    }
}
