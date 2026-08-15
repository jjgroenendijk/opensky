// SHOU record: a dragon shout, or one of the racial and creature powers built
// on the same machinery. A shout is a name, a description, and an ordered run
// of SNAM word entries, each pairing a word of power (WOOP) with the spell
// (SPEL) that word casts and the recovery time it costs.
//
// Every vanilla SHOU carries exactly three SNAM entries, including the powers
// that are not really shouts — those store three zeroed entries rather than
// none. The decoder does not enforce three: UESP records that an override with
// fewer leaks the missing entries in from the overridden record and one with
// more corrupts memory in the original engine, so OpenSky decodes whatever run
// is present and lets the consumer see the count.
//
// Skipped for now: ETYP, which xEdit documents on SHOU but no vanilla master
// authors; it is tallied as unread until a voice-slot consumer exists.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/SHOU"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SHOU
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(SHOU, 'Shout', ...)`
//     line 7173.
// Layout documented in docs/formats/magic-records.md.

import Foundation

nonisolated struct Shout: Equatable {
    /// One SNAM entry: 12 bytes, word FormID, spell FormID, recovery time.
    /// Both links are nil when the entry is the all-zero placeholder a
    /// non-shout power stores.
    struct Word: Equatable {
        let word: FormID?
        let spell: FormID?
        let recoveryTime: Float
    }

    /// SNAM is a fixed 12-byte struct (UESP; xEdit `wbStruct(SNAM, ...)`).
    static let wordEntrySize = 12

    let formID: FormID
    let editorID: String?
    let name: LString?
    /// MDOB — the STAT shown in the menu for this shout.
    let menuDisplayObject: FormID?
    let description: LString?
    /// The SNAM run in record order; the order is the unlock order in the
    /// original engine, so it is preserved rather than sorted.
    let words: [Word]
    let skipped: ReferenceRecordTally

    init(record: ESMRecord, localized: Bool) throws {
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
