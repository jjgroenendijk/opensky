// SCRL scroll: a spell wrapped in an inventory item. Its SPIT type and casting
// words are fixed on a scroll, but they decode anyway so a mod stays visible.
// Layout and sources: docs/formats/magic-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Scroll: Sendable {
    public let formID: FormID
    public let header: MagicItemHeader
    /// DATA — gold value and carry weight.
    public let itemValue: ItemValue
    /// SPIT. Nil when the field is absent or too short to decode.
    public let data: SpellItemData?
    public let effects: [MagicItemEffect]
    public let skipped: MagicEffectTally

    public var editorID: String? {
        header.fields.editorID
    }

    public var name: LString? {
        header.fields.name
    }

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "SCRL" else {
            throw ESMError.malformed("expected SCRL record, got \(record.type)")
        }
        var decoder = MagicItemFields(localized: localized)
        var itemValue = ItemValue.zero
        var skippedItemData = false
        for field in try record.fields() {
            guard field.type == "DATA" else {
                decoder.decode(field)
                continue
            }
            do {
                itemValue = try ItemValue(field: field)
            } catch {
                skippedItemData = true
            }
        }
        formID = FormID(record.formID)
        header = decoder.header
        self.itemValue = itemValue
        data = decoder.data
        effects = decoder.finishEffects()
        var skipped = decoder.skipped
        if skippedItemData {
            skipped.note(.malformedField("DATA"))
        }
        self.skipped = skipped
    }
}
