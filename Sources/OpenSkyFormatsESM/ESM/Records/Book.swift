// BOOK record. The DATA "teaches" word is a skill index or a SPEL FormID,
// chosen by a flag, so it decodes into an enum and keeps the raw word.
// Book text resolves through `.dlstrings`.
// Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Book: Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let teachesSkill = Flags(rawValue: 0x01)
        public static let cannotBeTaken = Flags(rawValue: 0x02)
        public static let teachesSpell = Flags(rawValue: 0x04)
    }

    /// What reading the book grants, decoded from DATA flags + teaches word.
    public enum Teaches: Equatable, Sendable {
        case nothing
        /// Actor-value index of the skill raised on read.
        case skill(Int32)
        /// SPEL record added on read.
        case spell(FormID)
    }

    /// DATA type byte. Vanilla SSE writes 0 everywhere; 255 is the legacy
    /// note/scroll marker. Unknown values keep their raw byte.
    public enum Kind: Equatable, Sendable {
        case book
        case note
        case unknown(UInt8)

        public init(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .book
            case 255: self = .note
            default: self = .unknown(rawValue)
            }
        }
    }

    public let formID: FormID
    public let fields: InventoryItemFields
    /// DESC — the book's body text.
    public let text: LString?
    /// CNAM — short description shown in the inventory pane.
    public let inventoryDescription: LString?
    public let flags: Flags
    public let kind: Kind
    public let teaches: Teaches
    /// DATA gold value and weight.
    public let itemValue: ItemValue

    public init(record: ESMRecord, localized: Bool) throws {
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
