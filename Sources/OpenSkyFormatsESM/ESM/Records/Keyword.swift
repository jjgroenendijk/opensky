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
import OpenSkyFormatsCore

nonisolated public enum ReferenceRecordSkipKind: Hashable, Sendable {
    case unknownField(FourCC)
    case malformedField(FourCC)
    case unknownDefaultObjectTag(FourCC)
}

nonisolated public struct ReferenceRecordTally: Equatable, Sendable {
    public private(set) var counts: [ReferenceRecordSkipKind: Int] = [:]

    public var total: Int {
        counts.values.reduce(0, +)
    }

    public mutating func note(_ kind: ReferenceRecordSkipKind) {
        counts[kind, default: 0] += 1
    }
}

/// CNAM byte RGBA used only to distinguish records in editor tooling.
nonisolated public struct ReferenceRecordColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(reader: inout BinaryReader) throws {
        try self.init(
            red: reader.readUInt8(),
            green: reader.readUInt8(),
            blue: reader.readUInt8(),
            alpha: reader.readUInt8()
        )
    }
}

nonisolated public struct Keyword: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let editorColor: ReferenceRecordColor?
    public let skipped: ReferenceRecordTally

    public init(record: ESMRecord) throws {
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

nonisolated public struct ActionRecord: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let editorColor: ReferenceRecordColor?
    public let skipped: ReferenceRecordTally

    public init(record: ESMRecord) throws {
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

nonisolated public struct ReferenceRecordFields: Sendable {
    public let editorID: String?
    public let editorColor: ReferenceRecordColor?
    public let skipped: ReferenceRecordTally

    public init(record: ESMRecord) throws {
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
