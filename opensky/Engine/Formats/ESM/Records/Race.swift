// RACE record decoded into engine types: the appearance subset needed to skin
// an actor, plus the DATA starting-attribute and regeneration floats the
// actor-value derivation needs (issue #194), plus the DATA fields that author a
// *non-primary* actor value — the seven skill bonuses, base carry weight, base
// mass and unarmed damage (issue #468). Spell lists, keywords, body-part data,
// tinting, face morphs and the movement floats are skipped deliberately.
//
// Per-gender skeleton: RACE gates gendered model blocks with 0-length MNAM
// (male) / FNAM (female) markers; the skeletal-model block that follows the
// first marker pair carries an ANAM zstring (path to the skeleton .nif). Later
// MNAM/FNAM markers open other blocks (face/body models, head presets) whose
// bodies hold MODL, not ANAM — so keying ANAM off the most recent MNAM/FNAM
// marker resolves the skeleton unambiguously (ANAM appears only in that one
// block). MODT model hashes are skipped.
//
// Reference: UESP "Skyrim Mod:Mod File Format/RACE"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/RACE
// Slot bit numbering: NifTools nif.xml BSDismemberBodyPartType (see
// BodyTemplate.swift).

import Foundation

nonisolated struct Race {
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
                flags = Race.decodeFlags(field) ?? flags
                stats = Race.decodeStats(field) ?? stats
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
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt32

        static let playable = Flags(rawValue: 0x0000_0001)
        /// Race uses baked FaceGen head assets (facegeom/facetint files);
        /// clear on creature races like cow/dog/bear.
        static let faceGenHead = Flags(rawValue: 0x0000_0002)
    }

    /// The DATA floats a level-1 actor of this race starts with, and the
    /// regeneration rates that refill them.
    ///
    /// Semantics from the Creation Kit's Race page, quoted rather than
    /// inferred: "Starting Health: Health for Level 1 actors of this race",
    /// and "Health Regen: The percentage of total Health that is regenerated
    /// each second" (<https://ck.uesp.net/wiki/Race>). The regen fields are
    /// therefore percentages, not fractions — vanilla `NordRace` stores 0.7,
    /// meaning 0.7% of maximum health per second.
    struct Stats: Equatable {
        var startingHealth: Float = 0
        var startingMagicka: Float = 0
        var startingStamina: Float = 0
        /// Percent of the maximum restored per second.
        var healthRegenPercent: Float = 0
        var magickaRegenPercent: Float = 0
        var staminaRegenPercent: Float = 0
        /// DATA 0x00: the seven "Skill N (Actor list value)" / "Racial bonus
        /// for skill N" byte pairs (UESP RACE DATA), in file order, with the
        /// pairs whose bonus is zero dropped — a race authors seven slots and
        /// vanilla leaves the unused ones at 0/0, which would otherwise read as
        /// a bonus to actor value 0 (`Aggression`).
        var skillBonuses: [SkillBonus] = []
        /// DATA 0x30 "Base Carry Weight", the base of actor value 32.
        var baseCarryWeight: Float = 0
        /// DATA 0x34 "Base Mass", the base of actor value 36.
        var baseMass: Float = 0
        /// DATA 0x60 "Unarmed Damage", the base of actor value 35.
        var unarmedDamage: Float = 0
    }

    /// One RACE DATA skill-bonus pair: a vanilla actor-value index and the
    /// number of points this race adds to it.
    struct SkillBonus: Equatable {
        /// Actor-value index, as `ActorValueIdentity` numbers them.
        var actorValue: Int32
        var bonus: Float
    }

    let formID: FormID
    let editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    let name: LString?
    /// WNAM — default skin, an ARMO applied when an actor wears nothing.
    let defaultSkin: FormID?
    /// BOD2/BODT biped slots + armor type; nil when absent.
    let bodyTemplate: BodyTemplate?
    /// DATA flags; empty when DATA is absent or too short.
    let flags: Flags
    /// DATA starting attributes and regen rates; all-zero when DATA is absent
    /// or too short to reach them.
    let stats: Stats
    /// ANAM under the male (MNAM) skeleton block.
    let maleSkeletonPath: String?
    /// ANAM under the female (FNAM) skeleton block.
    let femaleSkeletonPath: String?
    /// HEAD references under the male FaceGen head-data marker.
    let maleHeadParts: [FormID]
    /// HEAD references under the female FaceGen head-data marker.
    let femaleHeadParts: [FormID]

    init(record: ESMRecord, localized: Bool) throws {
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
        maleSkeletonPath = state.maleSkeletonPath
        femaleSkeletonPath = state.femaleSkeletonPath
        maleHeadParts = state.maleHeadParts
        femaleHeadParts = state.femaleHeadParts
    }

    /// DATA: skill bonuses (14 bytes + 2 pad) then male/female height +
    /// weight floats; flags live at 0x20 (UESP RACE DATA). Too-short DATA -> nil.
    private static func decodeFlags(_ field: ESMField) -> Flags? {
        guard field.data.count >= 0x24 else { return nil }
        var reader = BinaryReader(field.data)
        reader.skip(0x20)
        return try? Flags(rawValue: reader.readUInt32())
    }

    /// DATA continued (UESP RACE DATA, 128-byte v40 / 164-byte v43 struct):
    /// starting health / magicka / stamina are the three floats at 0x24, and
    /// health / magicka / stamina regen are the three at 0x54, after base
    /// carry weight, base mass, the two movement rates, size, and the head /
    /// hair / injured-health / shield fields.
    ///
    /// Read as independent windows rather than one long walk, so a DATA long
    /// enough for the starting attributes but not the regen block still yields
    /// the attributes. Vanilla ships neither shape, but a mod may.
    ///
    /// The non-primary actor values the same struct authors (issue #468) are
    /// read the same way: the seven skill-bonus pairs at 0x00, base carry
    /// weight at 0x30 and base mass at 0x34, and unarmed damage at 0x60, which
    /// is the first float after the three regen percentages.
    private static func decodeStats(_ field: ESMField) -> Stats? {
        guard field.data.count >= 0x30 else { return nil }
        var stats = Stats()
        stats.skillBonuses = decodeSkillBonuses(field)
        var reader = BinaryReader(field.data)
        reader.skip(0x24)
        stats.startingHealth = (try? reader.readFloat32()) ?? 0
        stats.startingMagicka = (try? reader.readFloat32()) ?? 0
        stats.startingStamina = (try? reader.readFloat32()) ?? 0
        if field.data.count >= 0x38 {
            stats.baseCarryWeight = (try? reader.readFloat32()) ?? 0
            stats.baseMass = (try? reader.readFloat32()) ?? 0
        }
        guard field.data.count >= 0x60 else { return stats }
        var regen = BinaryReader(field.data)
        regen.skip(0x54)
        stats.healthRegenPercent = (try? regen.readFloat32()) ?? 0
        stats.magickaRegenPercent = (try? regen.readFloat32()) ?? 0
        stats.staminaRegenPercent = (try? regen.readFloat32()) ?? 0
        guard field.data.count >= 0x64 else { return stats }
        stats.unarmedDamage = (try? regen.readFloat32()) ?? 0
        return stats
    }

    /// DATA 0x00: seven `(actor value, bonus)` byte pairs.
    ///
    /// A pair whose bonus is zero is dropped rather than stored, because a race
    /// that fills fewer than seven slots leaves the rest zeroed and a stored
    /// 0/0 pair is indistinguishable from "+0 to Aggression".
    private static func decodeSkillBonuses(_ field: ESMField) -> [SkillBonus] {
        guard field.data.count >= 0x0E else { return [] }
        var reader = BinaryReader(field.data)
        var bonuses: [SkillBonus] = []
        for _ in 0 ..< 7 {
            guard
                let actorValue = try? reader.readUInt8(),
                let bonus = try? reader.readUInt8(),
                bonus > 0
            else { continue }
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
