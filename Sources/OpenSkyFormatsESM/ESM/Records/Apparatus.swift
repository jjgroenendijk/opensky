// APPA alchemical apparatus: the shared carryable fields, value/weight DATA,
// quality, and description. Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

/// QUAL, an int32. An unknown value keeps its number.
nonisolated public enum ApparatusQuality: Equatable, Sendable {
    case novice
    case apprentice
    case journeyman
    case expert
    case master
    case unknown(Int32)

    public init(rawValue: Int32) {
        self = switch rawValue {
        case 0: .novice
        case 1: .apprentice
        case 2: .journeyman
        case 3: .expert
        case 4: .master
        default: .unknown(rawValue)
        }
    }

    public var rawValue: Int32 {
        switch self {
        case .novice: 0
        case .apprentice: 1
        case .journeyman: 2
        case .expert: 3
        case .master: 4
        case let .unknown(value): value
        }
    }
}

nonisolated public struct Apparatus: Sendable {
    public let formID: FormID
    public let fields: InventoryItemFields
    public let itemValue: ItemValue
    /// QUAL. Nil when the record has no QUAL field.
    public let quality: ApparatusQuality?
    /// DESC; localized plugins store a `.dlstrings` ID.
    public let description: LString?
    public let skipped: ItemFieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "APPA" else {
            throw ESMError.malformed("expected APPA record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var quality: ApparatusQuality?
        var description: LString?
        let decoded = try TalliedItemFields(record: record, localized: localized) { field in
            switch field.type {
            case "QUAL":
                var reader = BinaryReader(field.data)
                quality = try ApparatusQuality(rawValue: Int32(bitPattern: reader.readUInt32()))
            case "DESC":
                description = try LString(field: field, localized: localized)
            default:
                return false
            }
            return true
        }
        fields = decoded.fields
        itemValue = decoded.itemValue
        self.quality = quality
        self.description = description
        skipped = decoded.skipped
    }
}
