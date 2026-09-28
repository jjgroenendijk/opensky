// VTYP, the voice directory identity consumed by dialogue audio lookup.
// Reference: UESP Skyrim Mod:Mod File Format/VTYP and xEdit dev-4.1.6
// `wbRecord(VTYP, 'Voice Type', ...)` at line 6295.

import Foundation

nonisolated struct VoiceType {
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt8

        static let allowsDefaultDialogue = Flags(rawValue: 0x01)
        static let female = Flags(rawValue: 0x02)
    }

    let formID: FormID
    /// EDID is also the directory name under Sound/Voice/<plugin>/.
    let editorID: String?
    let flags: Flags
    let skipped: DialogueTally

    init(record: ESMRecord) throws {
        guard record.type == "VTYP" else {
            throw ESMError.malformed("expected VTYP record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var flags = Flags()
        var tally = DialogueTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "DNAM": flags = try Flags(rawValue: reader.readUInt8())
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        self.flags = flags
        skipped = tally
    }
}
