// ALCH record decoded into engine types: food, drink, potions and poisons. The
// type follows xEdit's name, Ingestible. DATA is a bare weight and the gold
// value lives in ENIT; the decoder fills the same `itemValue` pair from both.
// Effects resolve through MagicEffectStore. Layout: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Ingestible: Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// Gold value is authored, not derived from the effect costs.
        public static let noAutoCalc = Flags(rawValue: 0x0000_0001)
        public static let food = Flags(rawValue: 0x0000_0002)
        public static let medicine = Flags(rawValue: 0x0001_0000)
        public static let poison = Flags(rawValue: 0x0002_0000)
    }

    public let formID: FormID
    public let fields: InventoryItemFields
    /// Gold value from ENIT, carry weight from DATA.
    public let itemValue: ItemValue
    public let flags: Flags
    /// ENIT addiction link; vanilla never sets it.
    public let addiction: FormID?
    public let addictionChance: Float
    /// ENIT — SNDR played when the item is consumed.
    public let consumeSound: FormID?
    public let effects: [MagicItemEffect]
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "ALCH" else {
            throw ESMError.malformed("expected ALCH record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = InventoryItemFields()
        var effectList = MagicItemEffectList()
        var weight: Float = 0
        var enchantedItem = EnchantedItemData()
        var skipped = FieldTally()
        for field in try record.fields() {
            if try fields.decode(field: field, localized: localized) {
                continue
            }
            if try effectList.decode(field: field) {
                continue
            }
            switch field.type {
            case "DATA":
                // ALCH DATA is a bare float weight, not the shared 8-byte
                // value+weight struct.
                guard field.data.count >= 4 else { break }
                var reader = BinaryReader(field.data)
                weight = try reader.readFloat32()
            case "ENIT":
                enchantedItem = try EnchantedItemData(field: field)
            default:
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped
        self.fields = fields
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
