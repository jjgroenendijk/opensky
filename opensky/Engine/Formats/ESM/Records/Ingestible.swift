// ALCH record decoded into engine types: everything you consume — food,
// drink, potions and poisons. xEdit names the record "Ingestible"; the engine
// type follows that rather than the four-letter tag, since "alchemy" would
// suggest the crafting station.
//
// ALCH is the one carryable family whose DATA is *not* value + weight: DATA is
// a bare float32 weight, and the gold value lives in ENIT. The decoder fills
// the same engine-level `itemValue` pair from both so consumers never have to
// special-case it.
//
// ENIT is a 20-byte struct:
//   00 int32   gold value
//   04 uint32  flags — 0x00001 no auto-calc, 0x00002 food,
//              0x10000 medicine, 0x20000 poison
//   08 FormID  addiction (unused by vanilla)
//   0C float32 addiction chance
//   10 FormID  SNDR played on consume
//
// Effects (EFID/EFIT/CTDA runs) resolve through MagicEffectStore.
//
// Skipped: DEST destruction data, ETYP equip-type link.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/ALCH"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ALCH
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(ALCH, ...)` line 4042
//     — `wbFloat(DATA, 'Weight')` then the ENIT struct above.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct Ingestible {
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt32

        /// Gold value is authored, not derived from the effect costs.
        static let noAutoCalc = Flags(rawValue: 0x0000_0001)
        static let food = Flags(rawValue: 0x0000_0002)
        static let medicine = Flags(rawValue: 0x0001_0000)
        static let poison = Flags(rawValue: 0x0002_0000)
    }

    let formID: FormID
    let fields: InventoryItemFields
    /// DESC — flavour text; empty on most vanilla potions.
    let description: LString?
    /// Gold value from ENIT, carry weight from DATA.
    let itemValue: ItemValue
    let flags: Flags
    /// ENIT addiction link; vanilla never sets it.
    let addiction: FormID?
    let addictionChance: Float
    /// ENIT — SNDR played when the item is consumed.
    let consumeSound: FormID?
    let effects: [MagicItemEffect]

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "ALCH" else {
            throw ESMError.malformed("expected ALCH record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = InventoryItemFields()
        var effectList = MagicItemEffectList()
        var description: LString?
        var weight: Float = 0
        var enchantedItem = EnchantedItemData()
        for field in try record.fields() {
            if try fields.decode(field: field, localized: localized) {
                continue
            }
            if try effectList.decode(field: field) {
                continue
            }
            switch field.type {
            case "DESC":
                description = try LString(field: field, localized: localized)
            case "DATA":
                // ALCH DATA is a bare float weight, not the shared 8-byte
                // value+weight struct.
                guard field.data.count >= 4 else { break }
                var reader = BinaryReader(field.data)
                weight = try reader.readFloat32()
            case "ENIT":
                enchantedItem = try EnchantedItemData(field: field)
            default:
                break
            }
        }
        self.fields = fields
        self.description = description
        itemValue = ItemValue(value: enchantedItem.value, weight: weight)
        flags = enchantedItem.flags
        addiction = enchantedItem.addiction
        addictionChance = enchantedItem.addictionChance
        consumeSound = enchantedItem.consumeSound
        effects = effectList.finish()
    }

    /// ENIT decode kept out of `init` so the field switch stays small.
    private struct EnchantedItemData {
        var value: Int32 = 0
        var flags = Flags()
        var addiction: FormID?
        var addictionChance: Float = 0
        var consumeSound: FormID?

        init() {}

        init(field: ESMField) throws {
            guard field.data.count >= 20 else {
                throw ESMError.malformed(
                    "ALCH ENIT has \(field.data.count) bytes, expected 20"
                )
            }
            var reader = BinaryReader(field.data)
            value = try Int32(bitPattern: reader.readUInt32())
            flags = try Flags(rawValue: reader.readUInt32())
            let addictionID = try FormID(reader.readUInt32())
            addiction = addictionID.isNull ? nil : addictionID
            addictionChance = try reader.readFloat32()
            let soundID = try FormID(reader.readUInt32())
            consumeSound = soundID.isNull ? nil : soundID
        }
    }
}
