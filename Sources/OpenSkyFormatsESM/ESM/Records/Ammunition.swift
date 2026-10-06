// AMMO record decoded into engine types: arrows and bolts. DATA is 16 bytes in
// classic plugins and 20 in SSE, which adds weight, so the payload size picks
// the layout. A classic payload decodes with weight 0.
// Layout from UESP and xEdit: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Ammunition: Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let ignoresNormalWeaponResistance = Flags(rawValue: 0x0000_0001)
        public static let nonPlayable = Flags(rawValue: 0x0000_0002)
        /// Set on arrows, clear on crossbow bolts.
        public static let nonBolt = Flags(rawValue: 0x0000_0004)
    }

    public let formID: FormID
    public let fields: InventoryItemFields
    /// DATA gold value and weight (weight 0 on a classic 16-byte payload).
    public let itemValue: ItemValue
    /// DATA — the PROJ this ammunition launches; nil when unset.
    public let projectile: FormID?
    /// DATA base damage.
    public let damage: Float
    public let flags: Flags
    /// DESC — inventory description.
    public let description: LString?
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "AMMO" else {
            throw ESMError.malformed("expected AMMO record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = InventoryItemFields()
        var data = AmmoData()
        var description: LString?
        var skipped = FieldTally()
        for field in try record.fields() {
            if try fields.decode(field: field, localized: localized) {
                continue
            }
            switch field.type {
            case "DATA":
                data = try AmmoData(field: field)
            case "DESC":
                description = try LString(field: field, localized: localized)
            default:
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped
        self.fields = fields
        itemValue = ItemValue(value: data.value, weight: data.weight)
        projectile = data.projectile
        damage = data.damage
        flags = data.flags
        self.description = description
    }

    /// DATA decode kept out of `init` so the field switch stays small.
    private struct AmmoData {
        var projectile: FormID?
        var flags = Flags()
        var damage: Float = 0
        var value: Int32 = 0
        var weight: Float = 0

        init() {}

        init(field: ESMField) throws {
            guard field.data.count >= 16 else {
                throw ESMError.malformed(
                    "AMMO DATA has \(field.data.count) bytes, expected 16 or 20"
                )
            }
            var reader = BinaryReader(field.data)
            let projectileID = try FormID(reader.readUInt32())
            projectile = projectileID.isNull ? nil : projectileID
            flags = try Flags(rawValue: reader.readUInt32())
            damage = try reader.readFloat32()
            value = try Int32(bitPattern: reader.readUInt32())
            // SSE-only trailing weight; a classic payload leaves it 0.
            if field.data.count >= 20 {
                weight = try reader.readFloat32()
            }
        }
    }
}
