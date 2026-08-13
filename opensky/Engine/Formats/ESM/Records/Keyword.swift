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

nonisolated enum ReferenceRecordSkipKind: Hashable {
    case unknownField(FourCC)
    case malformedField(FourCC)
}

nonisolated struct ReferenceRecordTally: Equatable {
    private(set) var counts: [ReferenceRecordSkipKind: Int] = [:]

    var total: Int {
        counts.values.reduce(0, +)
    }

    mutating func note(_ kind: ReferenceRecordSkipKind) {
        counts[kind, default: 0] += 1
    }
}

/// CNAM byte RGBA used only to distinguish records in editor tooling.
nonisolated struct ReferenceRecordColor: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    fileprivate init(reader: inout BinaryReader) throws {
        try self.init(
            red: reader.readUInt8(),
            green: reader.readUInt8(),
            blue: reader.readUInt8(),
            alpha: reader.readUInt8()
        )
    }
}

nonisolated struct Keyword: Equatable {
    let formID: FormID
    let editorID: String?
    let editorColor: ReferenceRecordColor?
    let skipped: ReferenceRecordTally

    init(record: ESMRecord) throws {
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

nonisolated struct ActionRecord: Equatable {
    let formID: FormID
    let editorID: String?
    let editorColor: ReferenceRecordColor?
    let skipped: ReferenceRecordTally

    init(record: ESMRecord) throws {
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

nonisolated private struct ReferenceRecordFields {
    let editorID: String?
    let editorColor: ReferenceRecordColor?
    let skipped: ReferenceRecordTally

    init(record: ESMRecord) throws {
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
