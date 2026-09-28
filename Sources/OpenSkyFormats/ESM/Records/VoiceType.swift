// VTYP, the voice directory identity consumed by dialogue audio lookup.
// Reference: UESP Skyrim Mod:Mod File Format/VTYP and xEdit dev-4.1.6
// `wbRecord(VTYP, 'Voice Type', ...)` at line 6295.

import Foundation

nonisolated package struct VoiceType {
    package struct Flags: OptionSet, Equatable {
        package let rawValue: UInt8

        package init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        package static let allowsDefaultDialogue = Flags(rawValue: 0x01)
        package static let female = Flags(rawValue: 0x02)
    }

    package let formID: FormID
    /// EDID is also the directory name under Sound/Voice/<plugin>/.
    package let editorID: String?
    package let flags: Flags
    package let skipped: DialogueTally

    package init(record: ESMRecord) throws {
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
