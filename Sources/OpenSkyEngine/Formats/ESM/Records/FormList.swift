// FLST form lists: an editor ID followed by zero or more repeating LNAM
// FormID subrecords. List order is observable through Papyrus index access,
// so nulls and all other entries stay in file order.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/FLST" (EDID + repeating LNAM formid):
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FLST
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(FLST, ...)`,
//   which models LNAM as the repeating `FormIDs` array.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct FormList: Equatable {
    let formID: FormID
    let editorID: String?
    /// LNAM entries in file order. Nil is a legal null FormID element, not a
    /// missing entry. The format permits nulls even when a particular load
    /// order contains none.
    let entries: [FormID?]
    /// Number of LNAM payload tails shorter than one complete FormID.
    let malformedEntryCount: Int

    init(record: ESMRecord) throws {
        guard record.type == "FLST" else {
            throw ESMError.malformed("expected FLST record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var decodedEditorID: String?
        var decodedEntries: [FormID?] = []
        var malformedEntryCount = 0
        for field in try record.fields() {
            switch field.type {
            case "EDID":
                var reader = BinaryReader(field.data)
                decodedEditorID = try? reader.readZString()
            case "LNAM":
                var reader = BinaryReader(field.data)
                for _ in 0 ..< (field.data.count / 4) {
                    let entry = try FormID(reader.readUInt32())
                    decodedEntries.append(entry.isNull ? nil : entry)
                }
                if !field.data.count.isMultiple(of: 4) {
                    malformedEntryCount += 1
                }
            default:
                break
            }
        }
        editorID = decodedEditorID
        entries = decodedEntries
        self.malformedEntryCount = malformedEntryCount
    }
}
