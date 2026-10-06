// WEAP record decoded into engine types: weapons and the unarmed pseudo-weapon.
// DATA holds the inventory numbers, DNAM the combat numbers. CRDT is 16 bytes
// classic and 24 in SSE, so its size picks the layout. INAM names the swing
// impact set and BIDS the shield-bash set. Layout: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Weapon: Sendable {
    /// DNAM animation type. Decides the attack animation set and, with the
    /// keywords, what the weapon reads as in the UI.
    public enum AnimationType: UInt8, Equatable, Sendable {
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

    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public static let cannotDrop = Flags(rawValue: 0x0008)
        public static let embeddedWeapon = Flags(rawValue: 0x0020)
        public static let nonPlayable = Flags(rawValue: 0x0080)
    }

    /// CRDT — critical-hit numbers plus the SPEL applied on a critical.
    public struct CriticalData: Equatable, Sendable {
        public let damage: UInt16
        /// Chance multiplier; the CK constrains it to 0...1.5.
        public let percentMultiplier: Float
        /// True when the critical effect only fires on a killing blow.
        public let onDeath: Bool
        /// SPEL applied on a critical hit; nil when unset.
        public let effect: FormID?
    }

    public let formID: FormID
    public let fields: InventoryItemFields
    /// DESC — flavour text, set on artifacts and enchanted uniques.
    public let description: LString?
    /// DATA gold value and weight.
    public let itemValue: ItemValue
    /// DATA base damage before skill, perk and enchantment scaling.
    public let damage: UInt16
    /// DNAM animation type; nil when the byte is outside the documented set.
    public let animationType: AnimationType?
    /// DNAM attack speed multiplier.
    public let speed: Float
    /// DNAM reach multiplier.
    public let reach: Float
    public let flags: Flags
    /// DNAM governing skill as an actor-value index; nil when -1 (no skill).
    public let skill: Int32?
    /// DNAM stagger magnitude.
    public let stagger: Float
    public let criticalData: CriticalData?
    /// EITM — ENCH applied by the weapon; nil on unenchanted weapons.
    public let enchantment: FormID?
    /// EAMT — enchantment charge; feeds the gold-value formula.
    public let enchantmentCharge: UInt16?
    /// ETYP — EQUP slot ("BothHands", "EitherHand").
    public let equipType: FormID?
    /// CNAM — the WEAP this record templates from, nil when standalone.
    public let template: FormID?
    /// INAM — the IPDS an ordinary swing's impact resolves through; nil when
    /// the weapon names none.
    public let impactDataSet: FormID?
    /// BIDS — the IPDS a shield bash resolves through; nil when unset. Not the
    /// swing's set: UESP names the two separately and only bashing reads this.
    public let blockBashImpactDataSet: FormID?
    /// The fields no game system reads yet: sounds, scope, first-person model.
    public let details: WeaponDetails
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        var rest = try RecordFields(record: record, type: "WEAP", localized: localized)
        formID = rest.formID

        var fields = InventoryItemFields()
        var payload = WeaponFields()
        try rest.readEach { field in
            try fields.decode(field: field, localized: localized)
                || payload.decode(field: field, localized: localized)
        }
        details = WeaponDetails(&rest)
        skipped = rest.finish()
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
        impactDataSet = payload.impactDataSet
        blockBashImpactDataSet = payload.blockBashImpactDataSet
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
        var impactDataSet: FormID?
        var blockBashImpactDataSet: FormID?

        mutating func decode(field: ESMField, localized: Bool) throws -> Bool {
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
            case "INAM":
                impactDataSet = try InventoryItemFields.optionalFormID(field)
            case "BIDS":
                blockBashImpactDataSet = try InventoryItemFields.optionalFormID(field)
            default:
                return false
            }
            return true
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

/// WEAP fields beyond what combat reads. xEdit dev-4.1.6 names each one;
/// docs/formats/item-records.md.
nonisolated public struct WeaponDetails: Equatable, Sendable {
    /// MOD3 group — the model shown while aiming through a scope.
    public let scopeModel: ModelData?
    /// EFSD — the EFSH shown while scoped.
    public let scopeEffect: FormID?
    /// NNAM — the node an embedded weapon attaches to.
    public let embeddedWeaponNode: String?
    /// WNAM — the STAT drawn in first person.
    public let firstPersonModel: FormID?
    /// BAMT — the MATT a block hits instead of the weapon's own.
    public let alternateBlockMaterial: FormID?
    public let attackSound: FormID?
    public let attackSound2D: FormID?
    public let attackLoopSound: FormID?
    public let attackFailSound: FormID?
    public let idleSound: FormID?
    public let equipSound: FormID?
    public let unequipSound: FormID?
    /// VNAM — detection sound level: 0 loud, 1 normal, 2 silent, 3 very loud.
    public let detectionSoundLevel: UInt32?
    public let destructible: Destructible?

    init(_ fields: inout RecordFields) {
        scopeModel = fields.model(path: "MOD3", hashes: "MO3T", alternates: "MO3S")
        scopeEffect = fields.formID("EFSD")
        embeddedWeaponNode = fields.zstring("NNAM")
        firstPersonModel = fields.formID("WNAM")
        alternateBlockMaterial = fields.formID("BAMT")
        attackSound = fields.formID("SNAM")
        attackSound2D = fields.formID("XNAM")
        attackLoopSound = fields.formID("NAM7")
        attackFailSound = fields.formID("TNAM")
        idleSound = fields.formID("UNAM")
        equipSound = fields.formID("NAM9")
        unequipSound = fields.formID("NAM8")
        detectionSoundLevel = fields.uint32("VNAM")
        destructible = fields.destructible()
    }
}
