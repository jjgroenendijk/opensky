// RACE record: the appearance fields that skin an actor and the DATA fields
// that author its actor values. `RaceDetails` holds every other field.
// The skeleton ANAM sits in the block after the first MNAM/FNAM marker, so ANAM
// is keyed off the most recent marker (docs/formats/actors.md).
// Reference: UESP "Skyrim Mod:Mod File Format/RACE"; slot bits: nif.xml.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Race: Sendable {
    private enum Gender: Equatable {
        case male
        case female
    }

    private struct DecodeState {
        var editorID: String?
        var name: LString?
        var defaultSkin: FormID?
        var bodyTemplate: BodyTemplate?
        var flags = Flags()
        var stats = Stats()
        var spells: [FormID] = []
        var maleSkeletonPath: String?
        var femaleSkeletonPath: String?
        var gender: Gender?
        var headDataStarted = false
        var headGender: Gender?
        var maleHeadParts: [FormID] = []
        var femaleHeadParts: [FormID] = []

        mutating func consumeMetadata(_ field: ESMField, localized: Bool) throws -> Bool {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID": editorID = try reader.readZString()
            case "FULL": name = try LString(field: field, localized: localized)
            case "WNAM": defaultSkin = try FormID(reader.readUInt32())
            case "BOD2": bodyTemplate = try BodyTemplate(bod2: field)
            case "BODT": bodyTemplate = try BodyTemplate(bodt: field)
            case "DATA":
                flags = try Race.decodeFlags(field) ?? flags
                stats = try Race.decodeStats(field) ?? stats
            case "SPLO":
                try spells.append(FormID(reader.readUInt32()))
            default: return false
            }
            return true
        }

        mutating func consumeHeadData(_ field: ESMField) throws {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "MNAM": setGender(.male)
            case "FNAM": setGender(.female)
            case "NAM0":
                headDataStarted = true
                headGender = nil
            case "HEAD":
                guard headDataStarted else { return }
                let id = try FormID(reader.readUInt32())
                if headGender == .male {
                    maleHeadParts.append(id)
                } else if headGender == .female {
                    femaleHeadParts.append(id)
                }
            case "ANAM":
                let path = try reader.readZString()
                (maleSkeletonPath, femaleSkeletonPath) = Race.assignSkeleton(
                    path: path,
                    gender: gender,
                    male: maleSkeletonPath,
                    female: femaleSkeletonPath
                )
            default: break
            }
        }

        private mutating func setGender(_ value: Gender) {
            gender = value
            if headDataStarted {
                headGender = value
            }
        }
    }

    /// DATA uint32 flags at offset 0x20 (UESP RACE) — only the
    /// appearance-relevant bits are named.
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let playable = Flags(rawValue: 0x0000_0001)
        /// Race uses baked FaceGen head assets (facegeom/facetint files);
        /// clear on creature races like cow/dog/bear.
        public static let faceGenHead = Flags(rawValue: 0x0000_0002)
        public static let child = Flags(rawValue: 0x0000_0004)
    }

    /// Level-1 starting attributes and their regen rates. Regen is a percentage
    /// per second, not a fraction: `NordRace` stores 0.7 for 0.7%
    /// (<https://ck.uesp.net/wiki/Race>).
    public struct Stats: Equatable, Sendable {
        public var startingHealth: Float = 0
        public var startingMagicka: Float = 0
        public var startingStamina: Float = 0
        /// Percent of the maximum restored per second.
        public var healthRegenPercent: Float = 0
        public var magickaRegenPercent: Float = 0
        public var staminaRegenPercent: Float = 0
        /// DATA 0x00: the seven "Skill N (Actor list value)" / "Racial bonus
        /// for skill N" byte pairs (UESP RACE DATA), in file order, with the
        /// pairs whose bonus is zero dropped — a race authors seven slots and
        /// vanilla leaves the unused ones at 0/0, which would otherwise read as
        /// a bonus to actor value 0 (`Aggression`).
        public var skillBonuses: [SkillBonus] = []
        /// DATA 0x30 "Base Carry Weight", the base of actor value 32.
        public var baseCarryWeight: Float = 0
        /// DATA 0x34 "Base Mass", the base of actor value 36.
        public var baseMass: Float = 0
        /// DATA 0x60 "Unarmed Damage", the base of actor value 35.
        public var unarmedDamage: Float = 0

        public init(
            startingHealth: Float = 0,
            startingMagicka: Float = 0,
            startingStamina: Float = 0,
            healthRegenPercent: Float = 0,
            magickaRegenPercent: Float = 0,
            staminaRegenPercent: Float = 0,
            skillBonuses: [SkillBonus] = [],
            baseCarryWeight: Float = 0,
            baseMass: Float = 0,
            unarmedDamage: Float = 0
        ) {
            self.startingHealth = startingHealth
            self.startingMagicka = startingMagicka
            self.startingStamina = startingStamina
            self.healthRegenPercent = healthRegenPercent
            self.magickaRegenPercent = magickaRegenPercent
            self.staminaRegenPercent = staminaRegenPercent
            self.skillBonuses = skillBonuses
            self.baseCarryWeight = baseCarryWeight
            self.baseMass = baseMass
            self.unarmedDamage = unarmedDamage
        }
    }

    /// One RACE DATA skill-bonus pair: a vanilla actor-value index and the
    /// number of points this race adds to it.
    public struct SkillBonus: Equatable, Sendable {
        /// Actor-value index, as `ActorValueIdentity` numbers them.
        public var actorValue: Int32
        public var bonus: Float
    }

    public let formID: FormID
    public let editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    public let name: LString?
    /// WNAM — default skin, an ARMO applied when an actor wears nothing.
    public let defaultSkin: FormID?
    /// BOD2/BODT biped slots + armor type; nil when absent.
    public let bodyTemplate: BodyTemplate?
    /// DATA flags; empty when DATA is absent or too short.
    public let flags: Flags
    /// DATA starting attributes and regen rates; all-zero when DATA is absent
    /// or too short to reach them.
    public let stats: Stats
    /// SPLO — the spells and abilities every actor of this race carries. The
    /// `SPCT` count is not read: counting the entries cannot disagree with the
    /// file (see `ActorBase.spells`).
    public let spells: [FormID]
    /// ANAM under the male (MNAM) skeleton block.
    public let maleSkeletonPath: String?
    /// ANAM under the female (FNAM) skeleton block.
    public let femaleSkeletonPath: String?
    /// HEAD references under the male FaceGen head-data marker.
    public let maleHeadParts: [FormID]
    /// HEAD references under the female FaceGen head-data marker.
    public let femaleHeadParts: [FormID]
    /// Every other field: DATA in full, attacks, body models, movement, chargen head data.
    public let details: RaceDetails
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "RACE" else {
            throw ESMError.malformed("expected RACE record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var state = DecodeState()
        for field in try record.fields() {
            if try state.consumeMetadata(field, localized: localized) {
                continue
            }
            try state.consumeHeadData(field)
        }
        editorID = state.editorID
        name = state.name
        defaultSkin = state.defaultSkin
        bodyTemplate = state.bodyTemplate
        flags = state.flags
        stats = state.stats
        spells = state.spells
        maleSkeletonPath = state.maleSkeletonPath
        femaleSkeletonPath = state.femaleSkeletonPath
        maleHeadParts = state.maleHeadParts
        femaleHeadParts = state.femaleHeadParts
        var walk = try RaceFieldWalk(record: record, localized: localized)
        (details, skipped) = walk.run()
    }

    /// DATA: skill bonuses (14 bytes + 2 pad) then male/female height +
    /// weight floats; flags live at 0x20 (UESP RACE DATA). Too-short DATA -> nil.
    private static func decodeFlags(_ field: ESMField) throws -> Flags? {
        guard field.data.count >= 0x24 else { return nil }
        var reader = BinaryReader(field.data)
        reader.skip(0x20)
        return try Flags(rawValue: reader.readUInt32())
    }

    /// DATA starting attributes at 0x24, regen at 0x54, carry weight and mass at
    /// 0x30, unarmed damage at 0x60 (UESP RACE DATA). Each window is read on its
    /// own, so a DATA too short for the regen block still yields the attributes.
    private static func decodeStats(_ field: ESMField) throws -> Stats? {
        guard field.data.count >= 0x30 else { return nil }
        var stats = Stats()
        stats.skillBonuses = try decodeSkillBonuses(field)
        var reader = BinaryReader(field.data)
        reader.skip(0x24)
        stats.startingHealth = try reader.readFloat32()
        stats.startingMagicka = try reader.readFloat32()
        stats.startingStamina = try reader.readFloat32()
        if field.data.count >= 0x38 {
            stats.baseCarryWeight = try reader.readFloat32()
            stats.baseMass = try reader.readFloat32()
        }
        guard field.data.count >= 0x60 else { return stats }
        var regen = BinaryReader(field.data)
        regen.skip(0x54)
        stats.healthRegenPercent = try regen.readFloat32()
        stats.magickaRegenPercent = try regen.readFloat32()
        stats.staminaRegenPercent = try regen.readFloat32()
        guard field.data.count >= 0x64 else { return stats }
        stats.unarmedDamage = try regen.readFloat32()
        return stats
    }

    /// DATA 0x00: seven `(actor value, bonus)` byte pairs.
    ///
    /// A pair whose bonus is zero is dropped rather than stored, because a race
    /// that fills fewer than seven slots leaves the rest zeroed and a stored
    /// 0/0 pair is indistinguishable from "+0 to Aggression".
    private static func decodeSkillBonuses(_ field: ESMField) throws -> [SkillBonus] {
        guard field.data.count >= 0x0E else { return [] }
        var reader = BinaryReader(field.data)
        var bonuses: [SkillBonus] = []
        for _ in 0 ..< 7 {
            let actorValue = try reader.readUInt8()
            let bonus = try reader.readUInt8()
            guard bonus > 0 else { continue }
            bonuses.append(SkillBonus(actorValue: Int32(actorValue), bonus: Float(bonus)))
        }
        return bonuses
    }

    /// Routes a skeleton ANAM path to the gender named by the most recent
    /// MNAM/FNAM marker; keeps the first path seen per gender.
    private static func assignSkeleton(
        path: String,
        gender: Gender?,
        male: String?,
        female: String?
    ) -> (male: String?, female: String?) {
        var male = male
        var female = female
        if gender == .male, male == nil {
            male = path
        } else if gender == .female, female == nil {
            female = path
        }
        return (male, female)
    }
}
