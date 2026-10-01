// ARMA record: how an ARMO piece shows on a body, per gender, plus the races
// it applies to. MOD4/MOD5 first-person models are optional, so a missing one
// means "not on the arms". A higher DNAM priority draws over a lower one; no
// DNAM reads as 0. Layout and sources: docs/formats/armor.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ArmorAddon: Sendable {
    public let formID: FormID
    public let editorID: String?
    /// BOD2/BODT biped slots + armor type; nil when absent.
    public let bodyTemplate: BodyTemplate?
    /// RNAM — the one primary race the armature must have.
    public let primaryRace: FormID?
    /// MODL — extra races this armature also applies to.
    public let additionalRaces: [FormID]
    /// MOD2 — male biped model path relative to Data/ ("meshes\\...").
    public let maleModelPath: String?
    /// MOD3 — female biped model path.
    public let femaleModelPath: String?
    /// MOD4 — male first-person model path; nil when the armature shows
    /// nothing on the player's own arms.
    public let maleFirstPersonModelPath: String?
    /// MOD5 — female first-person model path.
    public let femaleFirstPersonModelPath: String?
    /// DNAM male draw priority; 0 when the record carries no DNAM.
    public let malePriority: UInt8
    /// DNAM female draw priority; 0 when the record carries no DNAM.
    public let femalePriority: UInt8
    /// DNAM weapon adjust — how far a weapon floats from its attachment point
    /// on an actor wearing this armature. Decoded now because the field is
    /// read here anyway; the hand attachment does not apply it yet.
    public let weaponAdjust: Float
    /// SNDD: the FSTS footstep set an actor wearing this armature walks with
    /// (xEdit `wbFormIDCk(SNDD, 'Footstep Sound', [FSTS, NULL])`). Only boot and
    /// bare-feet armatures carry one. Nil when absent or null.
    public let footstepSound: FormID?

    /// The draw priority that applies to one gender.
    public func priority(female: Bool) -> UInt8 {
        female ? femalePriority : malePriority
    }

    /// The first-person model for one gender, with the same cross-gender
    /// fallback the third-person selection uses: an armature that declares only
    /// MOD4 shows it on both genders rather than showing nothing.
    public func firstPersonModelPath(female: Bool) -> String? {
        let preferred = female ? femaleFirstPersonModelPath : maleFirstPersonModelPath
        return preferred ?? maleFirstPersonModelPath ?? femaleFirstPersonModelPath
    }

    public init(record: ESMRecord) throws {
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
