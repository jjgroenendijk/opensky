// ASTP association types: the gendered titles of a RELA pair and a family
// flag. The titles are plain zstrings, not lstrings.
// Layout and sources: docs/formats/relationships.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct AssociationType: Equatable, Sendable {
    /// DATA, uint32. Only bit 0 is named by either source.
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let familyAssociation = Flags(rawValue: 0x0000_0001)
    }

    public let formID: FormID
    public let editorID: String?
    /// MPRT — what the parent side is called when male.
    public let maleParentTitle: String?
    /// FPRT — what the parent side is called when female.
    public let femaleParentTitle: String?
    /// MCHT — what the child side is called when male. Optional in the record:
    /// a symmetric association such as an alliance names only the parent side.
    public let maleChildTitle: String?
    /// FCHT — what the child side is called when female.
    public let femaleChildTitle: String?
    public let flags: Flags
    public let skipped: ReferenceRecordTally

    public var isFamilyAssociation: Bool {
        flags.contains(.familyAssociation)
    }

    /// The title one side shows, preferring the gendered one the caller asked
    /// for and falling back to the other when the record only authored one.
    public func parentTitle(female: Bool) -> String? {
        female
            ? femaleParentTitle ?? maleParentTitle
            : maleParentTitle ?? femaleParentTitle
    }

    public func childTitle(female: Bool) -> String? {
        female
            ? femaleChildTitle ?? maleChildTitle
            : maleChildTitle ?? femaleChildTitle
    }

    public init(record: ESMRecord) throws {
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
