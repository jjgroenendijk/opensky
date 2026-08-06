// TXST record decoded into engine types: a texture set naming the individual
// map files (diffuse, normal, ...) used by a material. OpenSky reads the two
// maps terrain splatting needs today; the rest of the slots wait for the
// material pipeline that consumes them.
//
// Reference: UESP "Skyrim Mod:Mod File Format/TXST"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/TXST
// Cross-checked against xEdit dev-4.1.6 wbDefinitionsCommon.pas (wbTXST).
// Layout documented in docs/formats/land.md.

import Foundation

nonisolated struct TextureSet {
    let formID: FormID
    let editorID: String?
    /// TX00 — diffuse map path relative to Data/ (e.g. "textures\\...\\x.dds").
    let diffusePath: String?
    /// TX01 — normal/gloss map path.
    let normalPath: String?

    init(record: ESMRecord) throws {
        guard record.type == "TXST" else {
            throw ESMError.malformed("expected TXST record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var diffusePath: String?
        var normalPath: String?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "TX00":
                diffusePath = try reader.readZString()
            case "TX01":
                normalPath = try reader.readZString()
            // Skipped for now: TX02-TX07 (specular/env/height/etc. maps),
            // DODT (decal data), DNAM (texture set flags).
            default:
                break
            }
        }
        self.editorID = editorID
        self.diffusePath = diffusePath
        self.normalPath = normalPath
    }
}
