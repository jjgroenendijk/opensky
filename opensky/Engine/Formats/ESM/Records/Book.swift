// BOOK record decoded into engine types: books, tomes, notes, scrolls of
// text, and the skill/spell tomes that teach on read.
//
// DATA is a 16-byte struct:
//   0  uint8   flags — 0x01 teaches skill, 0x02 can't be taken,
//              0x04 teaches spell
//   1  uint8   type — 0 book/tome, 255 note/scroll (always 0 since SSE)
//   2  2 bytes unused
//   4  uint32  "teaches", read per the flags: an actor-value skill index when
//              0x01 is set, a SPEL FormID when 0x04 is set, otherwise unused
//   8  uint32  gold value
//   C  float32 weight
//
// The teaches word is the one genuinely ambiguous field: the same four bytes
// are a signed skill index or a FormID depending on a flag, so it decodes into
// an enum rather than being read twice. Neither flag set -> `.nothing`, and
// the raw word is kept so a mod that sets both (undefined in the spec) can
// still be inspected.
//
// DESC carries the book's body text and CNAM the short inventory blurb; both
// are lstrings, so a localized plugin stores string-table IDs. Book text
// resolves through the `.dlstrings` table, not `.strings` — see
// docs/formats/strings.md.
//
// Skipped: VMAD, DEST destruction data, INAM inventory-art STAT link.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/BOOK"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/BOOK
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(BOOK, ...)` line 4220
//     — flags/type/unused(2)/teaches union/value/weight.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct Book {
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt8

        static let teachesSkill = Flags(rawValue: 0x01)
        static let cannotBeTaken = Flags(rawValue: 0x02)
        static let teachesSpell = Flags(rawValue: 0x04)
    }

    /// What reading the book grants, decoded from DATA flags + teaches word.
    enum Teaches: Equatable {
        case nothing
        /// Actor-value index of the skill raised on read.
        case skill(Int32)
        /// SPEL record added on read.
        case spell(FormID)
    }

    /// DATA type byte. Vanilla SSE writes 0 everywhere; 255 is the legacy
    /// note/scroll marker. Unknown values keep their raw byte.
    enum Kind: Equatable {
        case book
        case note
        case unknown(UInt8)

        init(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .book
            case 255: self = .note
            default: self = .unknown(rawValue)
            }
        }
    }

    let formID: FormID
    let fields: InventoryItemFields
    /// DESC — the book's body text.
    let text: LString?
    /// CNAM — short description shown in the inventory pane.
    let inventoryDescription: LString?
    let flags: Flags
    let kind: Kind
    let teaches: Teaches
    /// DATA gold value and weight.
    let itemValue: ItemValue

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "BOOK" else {
            throw ESMError.malformed("expected BOOK record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = InventoryItemFields()
        var text: LString?
        var inventoryDescription: LString?
        var data = BookData()
        for field in try record.fields() {
            if try fields.decode(field: field, localized: localized) {
                continue
            }
            switch field.type {
            case "DESC":
                text = try LString(field: field, localized: localized)
            case "CNAM":
                inventoryDescription = try LString(field: field, localized: localized)
            case "DATA":
                data = try BookData(field: field)
            default:
                break
            }
        }
        self.fields = fields
        self.text = text
        self.inventoryDescription = inventoryDescription
        flags = data.flags
        kind = data.kind
        teaches = data.teaches
        itemValue = data.itemValue
    }

    /// DATA decode kept out of `init` so the field switch stays small.
    private struct BookData {
        var flags = Flags()
        var kind = Kind.book
        var teaches = Teaches.nothing
        var itemValue = ItemValue.zero

        init() {}

        init(field: ESMField) throws {
            guard field.data.count >= 16 else {
                throw ESMError.malformed(
                    "BOOK DATA has \(field.data.count) bytes, expected 16"
                )
            }
            var reader = BinaryReader(field.data)
            flags = try Flags(rawValue: reader.readUInt8())
            kind = try Kind(rawValue: reader.readUInt8())
            reader.skip(2) // unused
            let taught = try reader.readUInt32()
            teaches = if flags.contains(.teachesSpell) {
                .spell(FormID(taught))
            } else if flags.contains(.teachesSkill) {
                .skill(Int32(bitPattern: taught))
            } else {
                .nothing
            }
            itemValue = try ItemValue(
                value: Int32(bitPattern: reader.readUInt32()),
                weight: reader.readFloat32()
            )
        }
    }
}
