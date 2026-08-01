// WEAP record decoded into engine types: swords, axes, bows, staves, and the
// unarmed pseudo-weapon.
//
// Three payloads matter here and each has its own quirk.
//
// DATA, 10 bytes — the inventory numbers:
//   00 uint32  gold value
//   04 float32 weight
//   08 uint16  base damage
//
// DNAM, 100 bytes — the combat numbers. Only the fields the engine needs are
// read; the rest is padding, obsolete Fallout carry-over, or rumble data:
//   00 uint8   animation type (0 other ... 9 crossbow)
//   01 3 bytes unused
//   04 float32 speed
//   08 float32 reach (multiplier in fCombatDistance * NPCScale * reach)
//   0C uint16  flags — 0x08 can't drop, 0x20 embedded, 0x80 non-playable
//   4C int32   governing skill as an actor-value index, -1 for none
//   60 float32 stagger
//
// CRDT, critical-hit data — the one field whose SSE layout differs from
// Skyrim classic, so it is decoded by payload size rather than assumed:
//   classic, 16 bytes: uint16 damage, 2 unused, float32 percent multiplier,
//                      uint8 on-death, 3 unused, FormID SPEL effect
//   SSE,     24 bytes: same through the on-death byte, then 7 unused, the
//                      SPEL FormID at offset 0x10, then 4 more unused
// Anything else decodes as no critical data rather than being force-fit.
//
// Skipped: VMAD, DEST, MOD3 scope model, the impact-data/material links
// (BIDS/BAMT/INAM), the seven SNDR attack-sound links, NNAM embedded-weapon
// node, WNAM first-person model, VNAM detection level.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/WEAP"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WEAP
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(WEAP, ...)` line
//     10499 — DATA at 10530, DNAM at 10535 (member-by-member offsets), CRDT
//     at 10604 with the `IsSSE` unused-byte split.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct Weapon {
    /// DNAM animation type. Decides the attack animation set and, with the
    /// keywords, what the weapon reads as in the UI.
    enum AnimationType: UInt8, Equatable {
        case other = 0
        case oneHandSword = 1
        case oneHandDagger = 2
        case oneHandAxe = 3
        case oneHandMace = 4
        case twoHandSword = 5
        case twoHandAxe = 6
        case bow = 7
        case staff = 8
        case crossbow = 9
    }

    struct Flags: OptionSet, Equatable {
        let rawValue: UInt16

        static let ignoresNormalWeaponResistance = Flags(rawValue: 0x0001)
        static let cannotDrop = Flags(rawValue: 0x0008)
        static let embeddedWeapon = Flags(rawValue: 0x0020)
        static let nonPlayable = Flags(rawValue: 0x0080)
    }

    /// CRDT — critical-hit numbers plus the SPEL applied on a critical.
    struct CriticalData: Equatable {
        let damage: UInt16
        /// Chance multiplier; the CK constrains it to 0...1.5.
        let percentMultiplier: Float
        /// True when the critical effect only fires on a killing blow.
        let onDeath: Bool
        /// SPEL applied on a critical hit; nil when unset.
        let effect: FormID?
    }

    let formID: FormID
    let fields: InventoryItemFields
    /// DESC — flavour text, set on artifacts and enchanted uniques.
    let description: LString?
    /// DATA gold value and weight.
    let itemValue: ItemValue
    /// DATA base damage before skill, perk and enchantment scaling.
    let damage: UInt16
    /// DNAM animation type; nil when the byte is outside the documented set.
    let animationType: AnimationType?
    /// DNAM attack speed multiplier.
    let speed: Float
    /// DNAM reach multiplier.
    let reach: Float
    let flags: Flags
    /// DNAM governing skill as an actor-value index; nil when -1 (no skill).
    let skill: Int32?
    /// DNAM stagger magnitude.
    let stagger: Float
    let criticalData: CriticalData?
    /// EITM — ENCH applied by the weapon; nil on unenchanted weapons.
    let enchantment: FormID?
    /// EAMT — enchantment charge; feeds the gold-value formula in #179.
    let enchantmentCharge: UInt16?
    /// ETYP — EQUP slot ("BothHands", "EitherHand").
    let equipType: FormID?
    /// CNAM — the WEAP this record templates from, nil when standalone.
    let template: FormID?

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "WEAP" else {
            throw ESMError.malformed("expected WEAP record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = InventoryItemFields()
        var payload = WeaponFields()
        for field in try record.fields() {
            if try fields.decode(field: field, localized: localized) {
                continue
            }
            try payload.decode(field: field, localized: localized)
        }
        self.fields = fields
        description = payload.description
        itemValue = payload.itemValue
        damage = payload.damage
        animationType = payload.animationType
        speed = payload.speed
        reach = payload.reach
        flags = payload.flags
        skill = payload.skill
        stagger = payload.stagger
        criticalData = payload.criticalData
        enchantment = payload.enchantment
        enchantmentCharge = payload.enchantmentCharge
        equipType = payload.equipType
        template = payload.template
    }

    /// Accumulator for the WEAP-specific subrecords; exists so the field
    /// switch and the three struct decoders each stay inside the strict-lint
    /// complexity and body-length caps.
    private struct WeaponFields {
        var description: LString?
        var itemValue = ItemValue.zero
        var damage: UInt16 = 0
        var animationType: AnimationType?
        var speed: Float = 0
        var reach: Float = 0
        var flags = Flags()
        var skill: Int32?
        var stagger: Float = 0
        var criticalData: CriticalData?
        var enchantment: FormID?
        var enchantmentCharge: UInt16?
        var equipType: FormID?
        var template: FormID?

        mutating func decode(field: ESMField, localized: Bool) throws {
            switch field.type {
            case "DESC":
                description = try LString(field: field, localized: localized)
            case "DATA":
                try decodeData(field)
            case "DNAM":
                try decodeWeaponData(field)
            case "CRDT":
                criticalData = try Weapon.decodeCritical(field)
            case "EITM":
                enchantment = try InventoryItemFields.optionalFormID(field)
            case "EAMT":
                guard field.data.count >= 2 else { break }
                var reader = BinaryReader(field.data)
                enchantmentCharge = try reader.readUInt16()
            case "ETYP":
                equipType = try InventoryItemFields.optionalFormID(field)
            case "CNAM":
                template = try InventoryItemFields.optionalFormID(field)
            default:
                break
            }
        }

        /// DATA: uint32 value, float weight, uint16 damage.
        private mutating func decodeData(_ field: ESMField) throws {
            guard field.data.count >= 10 else {
                throw ESMError.malformed(
                    "WEAP DATA has \(field.data.count) bytes, expected 10"
                )
            }
            var reader = BinaryReader(field.data)
            itemValue = try ItemValue(
                value: Int32(bitPattern: reader.readUInt32()),
                weight: reader.readFloat32()
            )
            damage = try reader.readUInt16()
        }

        /// DNAM: 100 bytes; the engine reads offsets 0x00, 0x04, 0x08, 0x0C,
        /// 0x4C and 0x60 and skips the rest.
        private mutating func decodeWeaponData(_ field: ESMField) throws {
            guard field.data.count >= 0x64 else {
                throw ESMError.malformed(
                    "WEAP DNAM has \(field.data.count) bytes, expected 100"
                )
            }
            var reader = BinaryReader(field.data)
            animationType = try AnimationType(rawValue: reader.readUInt8())
            reader.skip(3) // unused
            speed = try reader.readFloat32()
            reach = try reader.readFloat32()
            flags = try Flags(rawValue: reader.readUInt16())
            reader.seek(to: 0x4C)
            let rawSkill = try Int32(bitPattern: reader.readUInt32())
            skill = rawSkill < 0 ? nil : rawSkill
            reader.seek(to: 0x60)
            stagger = try reader.readFloat32()
        }
    }

    /// CRDT decode. The SPEL link sits at a different offset in SSE than in
    /// Skyrim classic, so the payload size — not the plugin's form version —
    /// picks the layout: an SSE-only engine still has to read mod records
    /// carried over from classic.
    private static func decodeCritical(_ field: ESMField) throws -> CriticalData? {
        let size = field.data.count
        guard size == 16 || size == 24 else { return nil }
        var reader = BinaryReader(field.data)
        let damage = try reader.readUInt16()
        reader.skip(2) // unused
        let percentMultiplier = try reader.readFloat32()
        let onDeath = try reader.readUInt8() != 0
        reader.seek(to: size == 24 ? 0x10 : 0x0C)
        let effect = try FormID(reader.readUInt32())
        return CriticalData(
            damage: damage,
            percentMultiplier: percentMultiplier,
            onDeath: onDeath,
            effect: effect.isNull ? nil : effect
        )
    }
}
