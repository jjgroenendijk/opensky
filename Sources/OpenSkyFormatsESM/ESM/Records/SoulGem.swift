// SLGM soul gem: the shared carryable fields, value/weight DATA, the contained
// soul, the capacity, and the linked gem. Charge rules are not decoded here.
// Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

/// A soul size, as SOUL and SLCP store it. An unknown byte keeps its value.
nonisolated public enum SoulLevel: Equatable, Sendable {
    /// No soul. xEdit names this value "None".
    case empty
    case petty
    case lesser
    case common
    case greater
    case grand
    case unknown(UInt8)

    public init(rawValue: UInt8) {
        self = switch rawValue {
        case 0: .empty
        case 1: .petty
        case 2: .lesser
        case 3: .common
        case 4: .greater
        case 5: .grand
        default: .unknown(rawValue)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .empty: 0
        case .petty: 1
        case .lesser: 2
        case .common: 3
        case .greater: 4
        case .grand: 5
        case let .unknown(value): value
        }
    }
}

nonisolated public struct SoulGem: Sendable {
    public let formID: FormID
    public let fields: InventoryItemFields
    public let itemValue: ItemValue
    /// SOUL. Nil when the record has no SOUL field.
    public let containedSoul: SoulLevel?
    /// SLCP, the largest soul the gem holds. Nil when absent.
    public let capacity: SoulLevel?
    /// NAM0, another SLGM.
    public let linkedGem: FormID?
    /// Record-header flag `0x20000`, "Can Hold NPC Soul": the black soul gems.
    public let canHoldNPCSoul: Bool
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "SLGM" else {
            throw ESMError.malformed("expected SLGM record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var soul: SoulLevel?
        var capacity: SoulLevel?
        var linked: FormID?
        let decoded = try TalliedItemFields(record: record, localized: localized) { field in
            var reader = BinaryReader(field.data)
            switch field.type {
            case "SOUL": soul = try SoulLevel(rawValue: reader.readUInt8())
            case "SLCP": capacity = try SoulLevel(rawValue: reader.readUInt8())
            case "NAM0": linked = try InventoryItemFields.optionalFormID(field)
            default: return false
            }
            return true
        }
        fields = decoded.fields
        itemValue = decoded.itemValue
        containedSoul = soul
        self.capacity = capacity
        linkedGem = linked
        canHoldNPCSoul = record.flags.rawValue & 0x0002_0000 != 0
        skipped = decoded.skipped
    }
}
