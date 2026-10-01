// DOBJ: a packed array of 8-byte (use tag, FormID) entries. A zero tag is an
// empty slot. Tag meanings: DefaultObjectTagMeanings.swift.
// Layout and sources: docs/formats/records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct DefaultObjectTag: Hashable, Sendable, CustomStringConvertible {
    public let code: FourCC

    public init?(name: String) {
        let bytes = Array(name.utf8)
        guard bytes.count == 4 else { return nil }
        code = FourCC(
            rawValue: UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
        )
    }

    public init(code: FourCC) {
        self.code = code
    }

    public var description: String {
        code.description
    }

    public var meaning: String? {
        Self.knownMeanings[code]
    }

    public var isKnown: Bool {
        meaning != nil
    }
}

nonisolated public struct DefaultObjectEntry: Equatable, Sendable {
    public let tag: DefaultObjectTag
    /// A declared null is retained as an entry so an override can clear a
    /// lower-priority default without becoming indistinguishable from absence.
    public let object: FormID?
}

nonisolated public struct DefaultObjects: Equatable, Sendable {
    public let formID: FormID
    /// xEdit supplies this internal default for records that omit EDID, as all
    /// five vanilla masters do.
    public let editorID: String
    public let entries: [DefaultObjectEntry]
    public let skipped: ReferenceRecordTally

    public init(record: ESMRecord) throws {
        guard record.type == "DOBJ" else {
            throw ESMError.malformed("expected DOBJ record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var entries: [DefaultObjectEntry] = []
        var tally = ReferenceRecordTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "DNAM": try Self.decodeEntries(&reader, into: &entries, tally: &tally)
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID ?? "DefaultObjectManager"
        self.entries = entries
        skipped = tally
    }

    public func entry(tag name: String) -> DefaultObjectEntry? {
        guard let tag = DefaultObjectTag(name: name) else { return nil }
        return entries.last { $0.tag == tag }
    }

    private static func decodeEntries(
        _ reader: inout BinaryReader,
        into entries: inout [DefaultObjectEntry],
        tally: inout ReferenceRecordTally
    ) throws {
        while reader.bytesRemaining >= 8 {
            let code = try reader.readFourCC()
            let rawObject = try FormID(reader.readUInt32())
            guard code.rawValue != 0 else { continue }
            let tag = DefaultObjectTag(code: code)
            if !tag.isKnown {
                tally.note(.unknownDefaultObjectTag(code))
            }
            entries.append(DefaultObjectEntry(
                tag: tag,
                object: rawObject.isNull ? nil : rawObject
            ))
        }
        if reader.bytesRemaining != 0 {
            tally.note(.malformedField("DNAM"))
        }
    }
}
