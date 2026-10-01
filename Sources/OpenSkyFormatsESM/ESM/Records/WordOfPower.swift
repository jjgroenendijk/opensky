// WOOP word of power. FULL is the dragon-alphabet spelling ("B4"), TNAM the
// translation. An empty TNAM is normal vanilla data.
// Layout and sources: docs/formats/shouts-equip-slots.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct WordOfPower: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// FULL — the word in dragon-font transliteration.
    public let name: LString?
    /// TNAM — the word translated into the plugin's language.
    public let translation: LString?
    public let skipped: ReferenceRecordTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "WOOP" else {
            throw ESMError.malformed("expected WOOP record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var translation: LString?
        var tally = ReferenceRecordTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "FULL": name = try LString(field: field, localized: localized)
                case "TNAM": translation = try LString(field: field, localized: localized)
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        self.name = name
        self.translation = translation
        skipped = tally
    }
}
