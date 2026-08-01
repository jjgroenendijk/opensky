// AMMO record decoded into engine types: arrows and bolts.
//
// DATA grew by one field in SSE, so — as with WEAP CRDT — the payload size
// picks the layout rather than the plugin's form version, because an SSE-only
// engine still has to read classic-era mod records:
//   00 FormID  PROJ fired by this ammunition
//   04 uint32  flags — 0x01 ignores normal weapon resistance,
//                      0x02 non-playable, 0x04 non-bolt (i.e. an arrow)
//   08 float32 damage
//   0C uint32  gold value
//   10 float32 weight — SSE only; classic's 16-byte DATA stops at the value
// A classic 16-byte payload decodes with weight 0, which is what the engine
// would have used anyway: vanilla SSE writes 0.1 for every arrow and the
// carry system treats arrows as weightless.
//
// Skipped: DEST destruction data, ONAM short name.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/AMMO"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AMMO
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(AMMO, ...)` line 4087
//     — the `IsSSE(...)` pair at 4101 is the authority for the two sizes.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct Ammunition {
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt32

        static let ignoresNormalWeaponResistance = Flags(rawValue: 0x0000_0001)
        static let nonPlayable = Flags(rawValue: 0x0000_0002)
        /// Set on arrows, clear on crossbow bolts.
        static let nonBolt = Flags(rawValue: 0x0000_0004)
    }

    let formID: FormID
    let fields: InventoryItemFields
    /// DESC — flavour text; blank on vanilla arrows.
    let description: LString?
    /// DATA gold value and weight (weight 0 on a classic 16-byte payload).
    let itemValue: ItemValue
    /// DATA — the PROJ this ammunition launches; nil when unset.
    let projectile: FormID?
    /// DATA base damage.
    let damage: Float
    let flags: Flags

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "AMMO" else {
            throw ESMError.malformed("expected AMMO record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = InventoryItemFields()
        var description: LString?
        var data = AmmoData()
        for field in try record.fields() {
            if try fields.decode(field: field, localized: localized) {
                continue
            }
            switch field.type {
            case "DESC":
                description = try LString(field: field, localized: localized)
            case "DATA":
                data = try AmmoData(field: field)
            default:
                break
            }
        }
        self.fields = fields
        self.description = description
        itemValue = ItemValue(value: data.value, weight: data.weight)
        projectile = data.projectile
        damage = data.damage
        flags = data.flags
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
