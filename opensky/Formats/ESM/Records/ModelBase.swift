// MSTT/TREE/FURN/ACTI/CONT/DOOR records decoded into engine types: same
// EDID + MODL shape as STAT (StaticObject.swift) — a model path a placed
// reference resolves to. One shared decoder rather than five near-identical
// structs; type-specific fields stay unread until a milestone needs them.
// DOOR joins for M3.6: its MODL renders through the same static-model path;
// teleport data lives on placed REFR XTEL, not the base.
//
// Reference: UESP "Skyrim Mod:Mod File Format" per-record pages, all
// documenting EDID (zstring editor ID) + MODL (zstring model path) in the
// same position as STAT:
//   /MSTT  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MSTT
//   /TREE  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/TREE
//   /FURN  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FURN
//   /ACTI  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ACTI
//   /CONT  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CONT
//   /DOOR  https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DOOR
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct ModelBase {
    /// Record types this decoder accepts — all carry EDID + MODL where STAT
    /// does. CellSceneBuilder indexes each of these top groups separately.
    static let supportedTypes: Set<FourCC> = [
        "MSTT", "TREE", "FURN", "ACTI", "CONT", "DOOR"
    ]

    let formID: FormID
    let recordType: FourCC
    let editorID: String?
    /// MODL — mesh path relative to Data/ (e.g. "meshes\\trees\\treepineforest01.nif").
    /// Nil for bases with no model (rare outside markers).
    let modelPath: String?

    init(record: ESMRecord) throws {
        guard Self.supportedTypes.contains(record.type) else {
            throw ESMError.malformed(
                "expected MSTT/TREE/FURN/ACTI/CONT/DOOR record, got \(record.type)"
            )
        }
        formID = FormID(record.formID)
        recordType = record.type

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
