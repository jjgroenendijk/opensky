// MISC item: the shared carryable fields plus the 8-byte value/weight DATA.
// Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct MiscItem: Sendable {
    public let formID: FormID
    /// Shared carryable-item subrecords: EDID, FULL, MODL, OBND, keywords,
    /// icons, pickup/drop sounds.
    public let fields: InventoryItemFields
    /// DATA — gold value and carry weight.
    public let itemValue: ItemValue
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "MISC" else {
            throw ESMError.malformed("expected MISC record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = InventoryItemFields()
        var itemValue = ItemValue.zero
        var skipped = FieldTally()
        for field in try record.fields() {
            if try fields.decode(field: field, localized: localized) {
                continue
            }
            if field.type == "DATA" {
                itemValue = try ItemValue(field: field)
            } else {
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped
        self.fields = fields
        self.itemValue = itemValue
    }
}
