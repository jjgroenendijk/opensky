// ENCH record: identity, the ENIT header, and the shared effect run. Identity
// fields are decoded by name, so any other carryable-item field shows up in
// the unread-field tally. Layout and sources: docs/formats/enchantments.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Enchantment: Sendable {
    public let formID: FormID
    public let editorID: String?
    /// FULL — the name shown on an item this enchantment is applied to.
    public let name: LString?
    /// OBND. Always written, always zero on a vanilla ENCH.
    public let bounds: ObjectBounds?
    /// ENIT. Nil when the field is absent or too short to decode.
    public let data: EnchantmentItemData?
    public let effects: [MagicItemEffect]
    public let skipped: MagicEffectTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "ENCH" else {
            throw ESMError.malformed("expected ENCH record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var decoder = EnchantmentFields(localized: localized)
        for field in try record.fields() {
            decoder.decode(field)
        }
        editorID = decoder.editorID
        name = decoder.name
        bounds = decoder.bounds
        data = decoder.data
        effects = decoder.finishEffects()
        skipped = decoder.skipped
    }
}

/// Field accumulator for ENCH: the three identity fields, the ENIT struct, the
/// effect run, and the unread-field tally.
nonisolated private struct EnchantmentFields {
    let localized: Bool
    private(set) var editorID: String?
    private(set) var name: LString?
    private(set) var bounds: ObjectBounds?
    private(set) var data: EnchantmentItemData?
    private(set) var skipped = MagicEffectTally()
    private var effects = MagicItemEffectList()

    init(localized: Bool) {
        self.localized = localized
    }

    mutating func decode(_ field: ESMField) {
        do {
            switch field.type {
            case "EDID":
                var reader = BinaryReader(field.data)
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "OBND":
                bounds = try ObjectBounds(field: field)
            case "ENIT":
                data = try EnchantmentItemData(field: field)
            default:
                if try !effects.decode(field: field) {
                    skipped.note(.unknownField(field.type))
                }
            }
        } catch {
            skipped.note(.malformedField(field.type))
        }
    }

    mutating func finishEffects() -> [MagicItemEffect] {
        effects.finish()
    }
}
