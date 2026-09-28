// KYWD and AACT are editor-id tags with an editor-only colour. KYWD labels
// object records through KSIZ/KWDA; AACT labels IDLE roots.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/KYWD" and "/AACT":
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/KYWD
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AACT
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(KYWD, ...)`
//   and `wbRecord(AACT, ...)`, both EDID + byte-RGBA CNAM.
// Layout documented in docs/formats/keywords.md.

import Foundation

nonisolated package enum ReferenceRecordSkipKind: Hashable {
    case unknownField(FourCC)
    case malformedField(FourCC)
    case unknownDefaultObjectTag(FourCC)
}

nonisolated package struct ReferenceRecordTally: Equatable {
    package private(set) var counts: [ReferenceRecordSkipKind: Int] = [:]

    package var total: Int {
        counts.values.reduce(0, +)
    }

    package mutating func note(_ kind: ReferenceRecordSkipKind) {
        counts[kind, default: 0] += 1
    }
}

/// CNAM byte RGBA used only to distinguish records in editor tooling.
nonisolated package struct ReferenceRecordColor: Equatable {
    package let red: UInt8
    package let green: UInt8
    package let blue: UInt8
    package let alpha: UInt8

    package init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    package init(reader: inout BinaryReader) throws {
        try self.init(
            red: reader.readUInt8(),
            green: reader.readUInt8(),
            blue: reader.readUInt8(),
            alpha: reader.readUInt8()
        )
    }
}

nonisolated package struct Keyword: Equatable {
    package let formID: FormID
    package let editorID: String?
    package let editorColor: ReferenceRecordColor?
    package let skipped: ReferenceRecordTally

    package init(record: ESMRecord) throws {
        guard record.type == "KYWD" else {
            throw ESMError.malformed("expected KYWD record, got \(record.type)")
        }
        let decoded = try ReferenceRecordFields(record: record)
        formID = FormID(record.formID)
        editorID = decoded.editorID
        editorColor = decoded.editorColor
        skipped = decoded.skipped
    }
}

nonisolated package struct ActionRecord: Equatable {
    package let formID: FormID
    package let editorID: String?
    package let editorColor: ReferenceRecordColor?
    package let skipped: ReferenceRecordTally

    package init(record: ESMRecord) throws {
        guard record.type == "AACT" else {
            throw ESMError.malformed("expected AACT record, got \(record.type)")
        }
        let decoded = try ReferenceRecordFields(record: record)
        formID = FormID(record.formID)
        editorID = decoded.editorID
        editorColor = decoded.editorColor
        skipped = decoded.skipped
    }
}

nonisolated package struct ReferenceRecordFields {
    package let editorID: String?
    package let editorColor: ReferenceRecordColor?
    package let skipped: ReferenceRecordTally

    package init(record: ESMRecord) throws {
        var editorID: String?
        var editorColor: ReferenceRecordColor?
        var tally = ReferenceRecordTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "CNAM": editorColor = try ReferenceRecordColor(reader: &reader)
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        self.editorColor = editorColor
        skipped = tally
    }
}
