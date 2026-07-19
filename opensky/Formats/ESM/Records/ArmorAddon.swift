// ARMA record decoded into engine types: armature data — how an ARMO piece is
// displayed on a body. Holds the per-gender biped models and the races the
// armature applies to. First-person models (MOD4/MOD5), texture-swap lists,
// and MODT hashes are skipped.
//
// DNAM (12 bytes: male/female draw priorities, detection sound, weapon adjust)
// is skipped: it affects layering/sound, none of which the bind-pose skinning
// pass needs. Restore it when equip-slot priority resolution lands.
//
// MODL in ARMA is a 4-byte FormID naming an additional applicable RACE,
// repeated per race (distinct from MOD2/MOD3 which are model paths). Size-guard
// on 4 bytes.
//
// Reference: UESP "Skyrim Mod:Mod File Format/ARMA"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ARMA

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

    init(record: ESMRecord) throws {
        guard record.type == "ARMA" else {
            throw ESMError.malformed("expected ARMA record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var bodyTemplate: BodyTemplate?
        var primaryRace: FormID?
        var additionalRaces: [FormID] = []
        var maleModelPath: String?
        var femaleModelPath: String?
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
            case "MOD2":
                maleModelPath = try reader.readZString()
            case "MOD3":
                femaleModelPath = try reader.readZString()
            default:
                break
            }
        }
        self.editorID = editorID
        self.bodyTemplate = bodyTemplate
        self.primaryRace = primaryRace
        self.additionalRaces = additionalRaces
        self.maleModelPath = maleModelPath
        self.femaleModelPath = femaleModelPath
    }
}
