// ASTP association types: the vocabulary a RELA record names its pair with.
// Four titles — what each side is called, by gender — and one flag saying
// whether the association counts as family. Dialogue conditions reach them
// through `HasAssociationType` (issue #508); nothing here evaluates one.
//
// The four titles are plain zstrings rather than lstrings: xEdit spells them
// `wbString`, not `wbLString`, so they are editor vocabulary and never go
// through the localized string tables.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/ASTP":
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ASTP
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas
//   `wbRecord(ASTP, 'Association Type', ...)`.
// Layout documented in docs/formats/relationships.md.

import Foundation

nonisolated struct AssociationType: Equatable {
    /// DATA, uint32. Only bit 0 is named by either source.
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt32

        static let familyAssociation = Flags(rawValue: 0x0000_0001)
    }

    let formID: FormID
    let editorID: String?
    /// MPRT — what the parent side is called when male.
    let maleParentTitle: String?
    /// FPRT — what the parent side is called when female.
    let femaleParentTitle: String?
    /// MCHT — what the child side is called when male. Optional in the record:
    /// a symmetric association such as an alliance names only the parent side.
    let maleChildTitle: String?
    /// FCHT — what the child side is called when female.
    let femaleChildTitle: String?
    let flags: Flags
    let skipped: ReferenceRecordTally

    var isFamilyAssociation: Bool {
        flags.contains(.familyAssociation)
    }

    /// The title one side shows, preferring the gendered one the caller asked
    /// for and falling back to the other when the record only authored one.
    func parentTitle(female: Bool) -> String? {
        female
            ? femaleParentTitle ?? maleParentTitle
            : maleParentTitle ?? femaleParentTitle
    }

    func childTitle(female: Bool) -> String? {
        female
            ? femaleChildTitle ?? maleChildTitle
            : maleChildTitle ?? femaleChildTitle
    }

    init(record: ESMRecord) throws {
        guard record.type == "ASTP" else {
            throw ESMError.malformed("expected ASTP record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var titles = Titles()
        var flags = Flags()
        var tally = ReferenceRecordTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "MPRT": titles.maleParent = try reader.readZString()
                case "FPRT": titles.femaleParent = try reader.readZString()
                case "MCHT": titles.maleChild = try reader.readZString()
                case "FCHT": titles.femaleChild = try reader.readZString()
                case "DATA": flags = try Flags(rawValue: reader.readUInt32())
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        maleParentTitle = titles.maleParent
        femaleParentTitle = titles.femaleParent
        maleChildTitle = titles.maleChild
        femaleChildTitle = titles.femaleChild
        self.flags = flags
        skipped = tally
    }

    /// The four title fields, grouped so the field loop stays one accumulator
    /// rather than four locals.
    private struct Titles {
        var maleParent: String?
        var femaleParent: String?
        var maleChild: String?
        var femaleChild: String?
    }
}
