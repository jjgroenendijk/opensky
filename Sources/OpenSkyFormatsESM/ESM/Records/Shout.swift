// SHOU shout: a name, a description, and SNAM entries that pair a WOOP word
// with the SPEL it casts and its recovery time. Vanilla always has three
// entries, but the decoder takes whatever count is present.
// Layout and sources: docs/formats/shouts-equip-slots.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Shout: Equatable, Sendable {
    /// One SNAM entry: 12 bytes, word FormID, spell FormID, recovery time.
    /// Both links are nil when the entry is the all-zero placeholder a
    /// non-shout power stores.
    public struct Word: Equatable, Sendable {
        public let word: FormID?
        public let spell: FormID?
        public let recoveryTime: Float
    }

    /// SNAM is a fixed 12-byte struct (UESP; xEdit `wbStruct(SNAM, ...)`).
    public static let wordEntrySize = 12

    public let formID: FormID
    public let editorID: String?
    public let name: LString?
    /// MDOB — the STAT shown in the menu for this shout.
    public let menuDisplayObject: FormID?
    public let description: LString?
    /// The SNAM run in record order; the order is the unlock order in the
    /// original engine, so it is preserved rather than sorted.
    public let words: [Word]
    public let skipped: ReferenceRecordTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "SHOU" else {
            throw ESMError.malformed("expected SHOU record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var menuDisplayObject: FormID?
        var description: LString?
        var words: [Word] = []
        var tally = ReferenceRecordTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "FULL": name = try LString(field: field, localized: localized)
                case "MDOB": menuDisplayObject = try InventoryItemFields.optionalFormID(field)
                case "DESC": description = try LString(field: field, localized: localized)
                case "SNAM": try words.append(Self.word(&reader, size: field.data.count))
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        self.name = name
        self.menuDisplayObject = menuDisplayObject
        self.description = description
        self.words = words
        skipped = tally
    }

    private static func word(_ reader: inout BinaryReader, size: Int) throws -> Word {
        guard size >= wordEntrySize else {
            throw ESMError.malformed(
                "SHOU SNAM has \(size) bytes, expected \(wordEntrySize)"
            )
        }
        let word = try FormID(reader.readUInt32())
        let spell = try FormID(reader.readUInt32())
        return try Word(
            word: word.isNull ? nil : word,
            spell: spell.isNull ? nil : spell,
            recoveryTime: reader.readFloat32()
        )
    }
}
