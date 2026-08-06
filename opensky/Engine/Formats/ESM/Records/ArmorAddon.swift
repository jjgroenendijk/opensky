// ARMA record decoded into engine types: armature data — how an ARMO piece is
// displayed on a body. Holds the per-gender biped models, the per-gender
// first-person models, and the races the armature applies to. Texture-swap
// lists and MODT hashes are skipped.
//
// MOD4 and MOD5 are the male and female first-person models — the geometry the
// vanilla player sees on its own arms, skinned to the separate first-person rig
// under `meshes\actors\character\_1stperson\`. Both are optional and most
// armatures carry neither: only the pieces an arm can show (skin hands, the
// skin torso, gauntlets, rings) declare one, which is why item 14.7 treats a
// missing first-person model as "this piece is not on the arms" rather than as
// a failure. See docs/engine/behavior-runtime.md, "First person".
//
// DNAM (12 bytes) is decoded for equip-slot priority resolution (issue #178):
//   00 uint8   male draw priority
//   01 uint8   female draw priority
//   02 4 bytes weight-slider flags (xEdit) / one unknown uint32 (UESP)
//   06 uint8   detection sound value
//   07 1 byte  unused
//   08 float32 weapon adjust
// Only the two priorities and the weapon adjust are carried; the detection
// sound belongs to stealth and the weight sliders to body morphs, neither of
// which this engine has. UESP and xEdit disagree on how bytes 2-5 are named
// and agree on every offset that matters here.
//
// Priority semantics, from the Creation Kit wiki "ArmorAddon" page: "This is
// used to determine the order of the ArmorAddons. The base naked body (for all
// parts) is always 0. The armor for a torso would then be 5 and gloves that you
// want to draw over the ends of sleeves, for example, would be 10." So a higher
// priority draws over — and therefore hides — a lower one contesting the same
// biped slot. An ARMA with no DNAM at all reads as priority 0, which is the
// naked-body level and loses every contest, matching what the data means.
//
// MODL in ARMA is a 4-byte FormID naming an additional applicable RACE,
// repeated per race (distinct from MOD2/MOD3 which are model paths). Size-guard
// on 4 bytes.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/ARMA"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ARMA
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(ARMA, ...)` line 4180
//     — the DNAM `wbStruct` member list at 4184.
//   Creation Kit wiki "ArmorAddon" (priority meaning)
//     https://ck.uesp.net/wiki/Armor_Addon

import Foundation

nonisolated struct ArmorAddon {
    let formID: FormID
    let editorID: String?
    /// BOD2/BODT biped slots + armor type; nil when absent.
    let bodyTemplate: BodyTemplate?
    /// RNAM — the one primary race the armature must have.
    let primaryRace: FormID?
    /// MODL — extra races this armature also applies to.
    let additionalRaces: [FormID]
    /// MOD2 — male biped model path relative to Data/ ("meshes\\...").
    let maleModelPath: String?
    /// MOD3 — female biped model path.
    let femaleModelPath: String?
    /// MOD4 — male first-person model path; nil when the armature shows
    /// nothing on the player's own arms.
    let maleFirstPersonModelPath: String?
    /// MOD5 — female first-person model path.
    let femaleFirstPersonModelPath: String?
    /// DNAM male draw priority; 0 when the record carries no DNAM.
    let malePriority: UInt8
    /// DNAM female draw priority; 0 when the record carries no DNAM.
    let femalePriority: UInt8
    /// DNAM weapon adjust — how far a weapon floats from its attachment point
    /// on an actor wearing this armature. Decoded now because the field is
    /// read here anyway; the hand attachment does not apply it yet.
    let weaponAdjust: Float
    /// SNDD — the FSTS footstep set an actor wearing this armature walks with
    /// (issue #352). xEdit dev-4.1.6 names it `wbFormIDCk(SNDD, 'Footstep
    /// Sound', [FSTS, NULL])` at line 4216. Only the boot armatures carry one:
    /// vanilla's `NakedFeet*` armatures point at `FSTBarefootFootstepSet`,
    /// light boots at `FSTArmorLightFootstepSet`, and heavy boots at
    /// `FSTArmorHeavyFootstepSet`. Nil when absent or null.
    let footstepSound: FormID?

    /// The draw priority that applies to one gender.
    func priority(female: Bool) -> UInt8 {
        female ? femalePriority : malePriority
    }

    /// The first-person model for one gender, with the same cross-gender
    /// fallback the third-person selection uses: an armature that declares only
    /// MOD4 shows it on both genders rather than showing nothing.
    func firstPersonModelPath(female: Bool) -> String? {
        let preferred = female ? femaleFirstPersonModelPath : maleFirstPersonModelPath
        return preferred ?? maleFirstPersonModelPath ?? femaleFirstPersonModelPath
    }

    init(record: ESMRecord) throws {
        guard record.type == "ARMA" else {
            throw ESMError.malformed("expected ARMA record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var bodyTemplate: BodyTemplate?
        var primaryRace: FormID?
        var additionalRaces: [FormID] = []
        var models = ModelPaths()
        var priorities = DrawPriorities()
        var footstepSound: FormID?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "BOD2":
                bodyTemplate = try BodyTemplate(bod2: field)
            case "BODT":
                bodyTemplate = try BodyTemplate(bodt: field)
            case "RNAM":
                primaryRace = try FormID(reader.readUInt32())
            case "MODL":
                guard field.data.count == 4 else { break }
                try additionalRaces.append(FormID(reader.readUInt32()))
            case "DNAM":
                priorities = try DrawPriorities(field: field)
            case "SNDD":
                guard field.data.count == 4 else { break }
                let id = try FormID(reader.readUInt32())
                footstepSound = id.isNull ? nil : id
            default:
                // The four MOD2/MOD3/MOD4/MOD5 model paths, gathered by
                // `ModelPaths` so this switch stays inside the complexity cap.
                try models.read(field: field, reader: &reader)
            }
        }
        self.editorID = editorID
        self.bodyTemplate = bodyTemplate
        self.primaryRace = primaryRace
        self.additionalRaces = additionalRaces
        maleModelPath = models.male
        femaleModelPath = models.female
        maleFirstPersonModelPath = models.maleFirstPerson
        femaleFirstPersonModelPath = models.femaleFirstPerson
        malePriority = priorities.male
        femalePriority = priorities.female
        weaponAdjust = priorities.weaponAdjust
        self.footstepSound = footstepSound
    }

    /// The four model paths an ARMA can declare, gathered so the field loop
    /// keeps one local instead of four.
    private struct ModelPaths {
        var male: String?
        var female: String?
        var maleFirstPerson: String?
        var femaleFirstPerson: String?

        /// Reads `field` when it is one of the four model paths, and ignores
        /// every other field type.
        mutating func read(field: ESMField, reader: inout BinaryReader) throws {
            switch field.type {
            case "MOD2": male = try reader.readZString()
            case "MOD3": female = try reader.readZString()
            case "MOD4": maleFirstPerson = try reader.readZString()
            case "MOD5": femaleFirstPerson = try reader.readZString()
            default: break
            }
        }
    }

    /// The three DNAM members the engine keeps, with the all-zero reading a
    /// DNAM-less ARMA gets. A payload shorter than the documented 12 bytes
    /// decodes as far as it reaches rather than throwing: a missing priority
    /// degrades to the naked-body level, which is the same answer as no DNAM,
    /// while refusing the record would drop an armature that renders fine.
    private struct DrawPriorities {
        var male: UInt8 = 0
        var female: UInt8 = 0
        var weaponAdjust: Float = 0

        init() {}

        init(field: ESMField) throws {
            guard field.data.count >= 2 else { return }
            var reader = BinaryReader(field.data)
            male = try reader.readUInt8()
            female = try reader.readUInt8()
            guard field.data.count >= 12 else { return }
            reader.skip(6) // weight sliders + detection sound + one unused byte
            weaponAdjust = try reader.readFloat32()
        }
    }
}
