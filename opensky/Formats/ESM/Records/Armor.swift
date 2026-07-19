// ARMO record decoded into engine types: the appearance subset for skinning.
// An ARMO is one equippable piece (armor, jewelry, clothing, shield); its
// visible parts come from the armatures it references, one ARMA per MODL. The
// item's own ground/inventory display models (MOD2/MOD4 world-model paths),
// enchantment (EITM), value/weight (DATA), and keywords are skipped.
//
// MODL in ARMO is a 4-byte FormID pointing at an ARMA record (NOT a model
// path — unlike STAT/MODL), repeated once per armature. Size-guard on 4 bytes
// so any non-armature MODL variant is skipped rather than misread.
//
// Reference: UESP "Skyrim Mod:Mod File Format/ARMO"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ARMO

import Foundation

nonisolated struct Armor {
    let formID: FormID
    let editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    let name: LString?
    /// RNAM — race the piece fits / filters against (0x19 DefaultRace usually).
    let race: FormID?
    /// BOD2/BODT biped slots + armor type; nil when absent.
    let bodyTemplate: BodyTemplate?
    /// MODL armature list: ARMA FormIDs that supply the worn geometry.
    let armatures: [FormID]

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "ARMO" else {
            throw ESMError.malformed("expected ARMO record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var race: FormID?
        var bodyTemplate: BodyTemplate?
        var armatures: [FormID] = []
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "RNAM":
                race = try FormID(reader.readUInt32())
            case "BOD2":
                bodyTemplate = try BodyTemplate(bod2: field)
            case "BODT":
                bodyTemplate = try BodyTemplate(bodt: field)
            case "MODL":
                guard field.data.count == 4 else { break }
                try armatures.append(FormID(reader.readUInt32()))
            default:
                break
            }
        }
        self.editorID = editorID
        self.name = name
        self.race = race
        self.bodyTemplate = bodyTemplate
        self.armatures = armatures
    }
}
