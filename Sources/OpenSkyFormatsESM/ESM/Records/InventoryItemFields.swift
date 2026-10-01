// The fields every carryable base record shares, decoded once. `ItemValue` is
// separate because ALCH stores weight in DATA and gold value in ENIT.
// Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

/// The 8-byte DATA struct shared by MISC, INGR, KEYM and ARMO: gold value then
/// weight. xEdit types the value int32 (MISC, INGR) or uint32 (ARMO, AMMO);
/// int32 is the wider of the two on disk, so it is what the engine carries.
nonisolated public struct ItemValue: Equatable, Sendable {
    /// Gold value before enchantment adjustments.
    public let value: Int32
    /// Carry weight.
    public let weight: Float

    public static let zero = ItemValue(value: 0, weight: 0)

    public init(value: Int32, weight: Float) {
        self.value = value
        self.weight = weight
    }

    /// Decodes an 8-byte value+weight DATA. Shorter payloads throw: a wrong
    /// gold value or weight is worse than a skipped record, and every vanilla
    /// record writes the full struct.
    public init(field: ESMField) throws {
        guard field.data.count >= 8 else {
            throw ESMError.malformed(
                "\(field.type) has \(field.data.count) bytes, expected 8 (value + weight)"
            )
        }
        var reader = BinaryReader(field.data)
        value = try Int32(bitPattern: reader.readUInt32())
        weight = try reader.readFloat32()
    }
}

/// Mutable accumulator for the shared carryable-item fields. Records call
/// `decode(field:localized:)` first and handle only what it declines, which
/// keeps each record's own switch inside the strict-lint complexity cap.
nonisolated public struct InventoryItemFields: Sendable {
    public var editorID: String?
    /// FULL — display name; localized plugins store a string-table ID.
    public var name: LString?
    /// MODL — ground/world model path relative to Data/.
    public var modelPath: String?
    public var bounds: ObjectBounds?
    public var keywords = KeywordList()
    /// ICON — inventory image path relative to Data/.
    public var iconPath: String?
    /// MICO — message-menu image path relative to Data/.
    public var messageIconPath: String?
    /// YNAM — SNDR played on pickup.
    public var pickupSound: FormID?
    /// ZNAM — SNDR played on drop.
    public var dropSound: FormID?

    public init() {}

    /// Decodes `field` when it is one of the shared subrecords and reports
    /// whether it was consumed. DATA is deliberately *not* handled here: its
    /// layout is type-specific (8 bytes on MISC/INGR, 4 on ALCH, 10 on WEAP,
    /// 16 on BOOK, 16 or 20 on AMMO), so each record owns that case.
    public mutating func decode(field: ESMField, localized: Bool) throws -> Bool {
        if try keywords.decode(field: field) {
            return true
        }
        var reader = BinaryReader(field.data)
        switch field.type {
        case "EDID":
            editorID = try reader.readZString()
        case "FULL":
            name = try LString(field: field, localized: localized)
        case "MODL":
            modelPath = try reader.readZString()
        case "OBND":
            bounds = try ObjectBounds(field: field)
        case "ICON":
            iconPath = try reader.readZString()
        case "MICO":
            messageIconPath = try reader.readZString()
        case "YNAM":
            pickupSound = try Self.optionalFormID(field)
        case "ZNAM":
            dropSound = try Self.optionalFormID(field)
        default:
            return false
        }
        return true
    }

    /// Reads a 4-byte FormID link, mapping the null sentinel and any
    /// unexpected payload length onto nil.
    public static func optionalFormID(_ field: ESMField) throws -> FormID? {
        guard field.data.count >= 4 else { return nil }
        var reader = BinaryReader(field.data)
        let formID = try FormID(reader.readUInt32())
        return formID.isNull ? nil : formID
    }
}
