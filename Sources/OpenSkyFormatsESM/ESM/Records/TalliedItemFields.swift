// Field loop for the carryable records that tally what they do not read (KEYM,
// SLGM, APPA). A malformed field is counted and dropped, so a truncated field
// costs only itself. Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum ItemFieldSkipKind: SkipTallyKind {
    case unknownField(FourCC)
    case malformedField(FourCC)

    public var name: String {
        switch self {
        case let .unknownField(type): "unknown \(type)"
        case let .malformedField(type): "malformed \(type)"
        }
    }
}

public typealias ItemFieldTally = SkipTally<ItemFieldSkipKind>

/// The shared carryable fields, the 8-byte value/weight DATA, and the tally,
/// after one pass over a record.
nonisolated struct TalliedItemFields {
    private(set) var fields = InventoryItemFields()
    private(set) var itemValue = ItemValue.zero
    private(set) var skipped = ItemFieldTally()

    /// Decodes every field of `record`. `own` handles the record's own fields
    /// and returns false for a field it does not know, which is then tallied.
    init(
        record: ESMRecord,
        localized: Bool,
        own: (ESMField) throws -> Bool
    ) throws {
        for field in try record.fields() {
            do {
                if try fields.decode(field: field, localized: localized) {
                    continue
                }
                if field.type == "DATA" {
                    itemValue = try ItemValue(field: field)
                } else if try !own(field) {
                    skipped.note(.unknownField(field.type))
                }
            } catch {
                skipped.note(.malformedField(field.type))
            }
        }
    }
}
