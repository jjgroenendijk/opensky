// LTEX record decoded into engine types: a named landscape texture that a
// LAND quadrant/layer references, pointing at the TXST texture set that holds
// the actual diffuse/normal paths.
//
// Reference: UESP "Skyrim Mod:Mod File Format/LTEX"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LTEX
// Cross-checked against xEdit dev-4.1.6 wbDefinitionsCommon.pas (wbLTEX).
// Layout documented in docs/formats/land.md.

import Foundation

nonisolated struct LandTexture {
    let formID: FormID
    let editorID: String?
    /// TNAM — the TXST texture set this landscape texture draws from.
    let textureSet: FormID?

    init(record: ESMRecord) throws {
        guard record.type == "LTEX" else {
            throw ESMError.malformed("expected LTEX record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var textureSet: FormID?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "TNAM":
                textureSet = try FormID(reader.readUInt32())
            // Skipped for now: MNAM (material type), HNAM (havok friction/
            // restitution), SNAM (texture specular), GNAM (grass FormIDs).
            default:
                break
            }
        }
        self.editorID = editorID
        self.textureSet = textureSet
    }
}
