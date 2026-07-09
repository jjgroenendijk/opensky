// STAT record decoded into engine types: the model path a placed reference
// resolves to. MODL is a windows path relative to Data/ ("meshes\\..."),
// looked up through the VFS. MODT (texture hashes), DNAM (max angle +
// material) and LOD fields are skipped until rendering needs them.
//
// Reference: UESP "Skyrim Mod:Mod File Format/STAT"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/STAT
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct StaticObject {
    let formID: FormID
    let editorID: String?
    /// MODL — mesh path relative to Data/ (e.g. "meshes\\clutter\\cup.nif").
    /// Nil for marker statics that have no model.
    let modelPath: String?

    init(record: ESMRecord) throws {
        guard record.type == "STAT" else {
            throw ESMError.malformed("expected STAT record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var modelPath: String?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "MODL":
                modelPath = try reader.readZString()
            default:
                break
            }
        }
        self.editorID = editorID
        self.modelPath = modelPath
    }
}
