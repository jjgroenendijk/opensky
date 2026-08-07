// RACE record decoded into engine types: the appearance subset needed to skin
// an actor, plus the DATA starting-attribute and regeneration floats the
// actor-value derivation needs (issue #194). Spell lists, keywords, body-part
// data, tinting, and face morphs are skipped deliberately, as are the DATA
// skill bonuses (M18) and the movement floats.
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

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "RACE" else {
            throw ESMError.malformed("expected RACE record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var defaultSkin: FormID?
        var bodyTemplate: BodyTemplate?
        var flags = Flags()
        var stats = Stats()
        var maleSkeletonPath: String?
        var femaleSkeletonPath: String?
        var gender: Gender?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "WNAM":
                defaultSkin = try FormID(reader.readUInt32())
            case "BOD2":
                bodyTemplate = try BodyTemplate(bod2: field)
            case "BODT":
                bodyTemplate = try BodyTemplate(bodt: field)
            case "DATA":
                flags = Self.decodeFlags(field) ?? flags
                stats = Self.decodeStats(field) ?? stats
            case "MNAM":
                gender = .male
            case "FNAM":
                gender = .female
            case "ANAM":
                // Only the skeleton block emits ANAM; first path per gender
                // wins so any stray later ANAM cannot clobber it.
                let path = try reader.readZString()
                (maleSkeletonPath, femaleSkeletonPath) = Self.assignSkeleton(
                    path: path,
                    gender: gender,
                    male: maleSkeletonPath,
                    female: femaleSkeletonPath
                )
            default:
                break
            }
        }
        self.editorID = editorID
        self.name = name
        self.defaultSkin = defaultSkin
        self.bodyTemplate = bodyTemplate
        self.flags = flags
        self.stats = stats
        self.maleSkeletonPath = maleSkeletonPath
        self.femaleSkeletonPath = femaleSkeletonPath
    }

    /// DATA: skill boosts (14 bytes + 2 pad) then male/female height +
    /// weight floats; flags live at 0x20 (UESP RACE DATA). The skill payload
    /// stays undecoded until M18; too-short DATA -> nil.
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
    /// Read as two independent windows rather than one long walk, so a DATA
    /// long enough for the starting attributes but not the regen block still
    /// yields the attributes. Vanilla ships neither shape, but a mod may.
    private static func decodeStats(_ field: ESMField) -> Stats? {
        guard field.data.count >= 0x30 else { return nil }
        var stats = Stats()
        var reader = BinaryReader(field.data)
        reader.skip(0x24)
        stats.startingHealth = (try? reader.readFloat32()) ?? 0
        stats.startingMagicka = (try? reader.readFloat32()) ?? 0
        stats.startingStamina = (try? reader.readFloat32()) ?? 0
        guard field.data.count >= 0x60 else { return stats }
        var regen = BinaryReader(field.data)
        regen.skip(0x54)
        stats.healthRegenPercent = (try? regen.readFloat32()) ?? 0
        stats.magickaRegenPercent = (try? regen.readFloat32()) ?? 0
        stats.staminaRegenPercent = (try? regen.readFloat32()) ?? 0
        return stats
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
