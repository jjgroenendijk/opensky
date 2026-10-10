// KEYM key: the shared carryable fields plus the 8-byte value/weight DATA.
// Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct KeyItem: Sendable {
    public let formID: FormID
    public let fields: InventoryItemFields
    public let itemValue: ItemValue
    /// Record-header flag `0x04`, "Non-Playable".
    public let isPlayable: Bool
    /// Fields the decoder does not read, such as VMAD and the destruction data.
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "KEYM" else {
            throw ESMError.malformed("expected KEYM record, got \(record.type)")
        }
        formID = FormID(record.formID)
        let decoded = try TalliedItemFields(record: record, localized: localized) { _ in false }
        fields = decoded.fields
        itemValue = decoded.itemValue
        isPlayable = record.flags.rawValue & 0x04 == 0
        skipped = decoded.skipped
    }
}
