// INGR ingredient. Same effect list as ALCH, but with the usual 8-byte
// value/weight DATA and an 8-byte ENIT. Which effects are discovered is save
// state. Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Ingredient: Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// Ingredient value is authored rather than summed from the effects.
        public static let noAutoCalc = Flags(rawValue: 0x0000_0001)
        public static let food = Flags(rawValue: 0x0000_0002)
        public static let referencesPersist = Flags(rawValue: 0x0000_0100)
    }

    public let formID: FormID
    public let fields: InventoryItemFields
    /// DATA — gold value and carry weight.
    public let itemValue: ItemValue
    /// ENIT value word. Distinct from `itemValue.value`: this one feeds the
    /// auto-calc cost formula, the DATA one is the price.
    public let autoCalcValue: Int32
    public let flags: Flags
    public let effects: [MagicItemEffect]
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "INGR" else {
            throw ESMError.malformed("expected INGR record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = InventoryItemFields()
        var effectList = MagicItemEffectList()
        var itemValue = ItemValue.zero
        var autoCalcValue: Int32 = 0
        var flags = Flags()
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
                itemValue = try ItemValue(field: field)
            case "ENIT":
                guard field.data.count >= 8 else { break }
                var reader = BinaryReader(field.data)
                autoCalcValue = try Int32(bitPattern: reader.readUInt32())
                flags = try Flags(rawValue: reader.readUInt32())
            default:
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped
        self.fields = fields
        self.itemValue = itemValue
        self.autoCalcValue = autoCalcValue
        self.flags = flags
        effects = effectList.finish()
    }
}
