// OTFT record decoded into engine types: an outfit — the set of items an actor
// wears by default (DOFT on NPC_). INAM is a single subrecord holding a packed
// array of uint32 FormIDs; each entry is an ARMO piece or an LVLI leveled item
// list. Item count is the field size / 4.
//
// Reference: UESP "Skyrim Mod:Mod File Format/OTFT"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/OTFT

import Foundation

nonisolated struct Outfit {
    let formID: FormID
    let editorID: String?
    /// INAM — outfit contents, each an ARMO or LVLI FormID.
    let items: [FormID]

    init(record: ESMRecord) throws {
        guard record.type == "OTFT" else {
            throw ESMError.malformed("expected OTFT record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var items: [FormID] = []
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "INAM":
                guard field.data.count % 4 == 0 else {
                    throw ESMError.malformed(
                        "OTFT \(formID) INAM has \(field.data.count) bytes, not a multiple of 4"
                    )
                }
                for _ in 0 ..< (field.data.count / 4) {
                    try items.append(FormID(reader.readUInt32()))
                }
            default:
                break
            }
        }
        self.editorID = editorID
        self.items = items
    }
}
