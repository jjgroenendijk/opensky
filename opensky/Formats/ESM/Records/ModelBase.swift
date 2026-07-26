// MSTT/TREE/FURN/ACTI/CONT/DOOR records decoded into engine types: same
// EDID + FULL + MODL shape — a named model a placed reference resolves to.
// One shared decoder rather than six near-identical structs; type-specific
// fields stay unread until a milestone needs them.
// DOOR joins for M3.6: its MODL renders through the same static-model path;
// teleport data lives on placed REFR XTEL, not the base.
//
// Reference: UESP "Skyrim Mod:Mod File Format" per-record pages document
// the type layouts below. xEdit dev-4.1.6 wbDefinitionsTES5.pas is the
// cross-type authority for FULL, RNAM, FNAM, MNAM, and suppression flags:
// https://github.com/TES5Edit/TES5Edit/blob/fd1e36020b2b5b6217e553dc0038983146a2e2dd/Core/wbDefinitionsTES5.pas
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
    /// FULL — in-game display name; localized plugins store a string-table ID.
    let name: LString?
    /// ACTI RNAM — custom activation verb such as "Mine" or "Place".
    let activateTextOverride: LString?
    /// Record-specific flags can suppress manual use-key activation.
    let allowsManualInteraction: Bool
    /// MODL — mesh path relative to Data/ (e.g. "meshes\\trees\\treepineforest01.nif").
    /// Nil for bases with no model (rare outside markers).
    let modelPath: String?

    init(record: ESMRecord, localized: Bool = false) throws {
        guard Self.supportedTypes.contains(record.type) else {
            throw ESMError.malformed(
                "expected MSTT/TREE/FURN/ACTI/CONT/DOOR record, got \(record.type)"
            )
        }
        formID = FormID(record.formID)
        recordType = record.type

        var editorID: String?
        var name: LString?
        var activateTextOverride: LString?
        var modelPath: String?
        var doorFlags: UInt8 = 0
        var furnitureMarkers: UInt32 = 0
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "MODL":
                modelPath = try reader.readZString()
            case "RNAM" where record.type == "ACTI":
                activateTextOverride = try LString(field: field, localized: localized)
            case "FNAM" where record.type == "DOOR":
                doorFlags = try reader.readUInt8()
            case "MNAM" where record.type == "FURN":
                furnitureMarkers = try reader.readUInt32()
            default:
                break
            }
        }
        self.editorID = editorID
        self.name = name
        self.activateTextOverride = activateTextOverride
        // xEdit dev-4.1.6: ACTI header bit 20 is Ignore Object
        // Interaction; DOOR FNAM bit 1 is Automatic; FURN MNAM bit 25
        // disables activation.
        allowsManualInteraction = !(record.type == "ACTI"
            && record.flags.rawValue & (1 << 20) != 0)
            && !(record.type == "DOOR" && doorFlags & 0x02 != 0)
            && !(record.type == "FURN" && furnitureMarkers & 0x0200_0000 != 0)
        self.modelPath = modelPath
    }
}
