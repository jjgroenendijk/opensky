// DOBJ is a packed array of 8-byte (four-character use tag, FormID) entries.
// Empty array slots carry a zero tag and are not declarations. The semantic
// tag table lives in DefaultObjectTagMeanings.swift.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/DOBJ"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DOBJ
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbDOBJObjectsTES5` and
//     `wbRecord(DOBJ, ...)`, lines 6560-6976.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct DefaultObjectTag: Hashable, Sendable, CustomStringConvertible {
    let code: FourCC

    init?(name: String) {
        let bytes = Array(name.utf8)
        guard bytes.count == 4 else { return nil }
        code = FourCC(
            rawValue: UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
        )
    }

    init(code: FourCC) {
        self.code = code
    }

    var description: String {
        code.description
    }

    var meaning: String? {
        Self.knownMeanings[code]
    }

    var isKnown: Bool {
        meaning != nil
    }
}

nonisolated struct DefaultObjectEntry: Equatable, Sendable {
    let tag: DefaultObjectTag
    /// A declared null is retained as an entry so an override can clear a
    /// lower-priority default without becoming indistinguishable from absence.
    let object: FormID?
}

nonisolated struct DefaultObjects: Equatable {
    let formID: FormID
    /// xEdit supplies this internal default for records that omit EDID, as all
    /// five vanilla masters do.
    let editorID: String
    let entries: [DefaultObjectEntry]
    let skipped: ReferenceRecordTally

    init(record: ESMRecord) throws {
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

    func entry(tag name: String) -> DefaultObjectEntry? {
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
