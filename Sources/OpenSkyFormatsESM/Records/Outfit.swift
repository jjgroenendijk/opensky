// OTFT outfit: the items an actor wears by default (NPC_ DOFT). INAM is a
// packed array of ARMO or LVLI FormIDs. Layout: docs/formats/actors.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Outfit: Sendable {
    public let formID: FormID
    public let editorID: String?
    /// INAM — outfit contents, each an ARMO or LVLI FormID.
    public let items: [FormID]
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "OTFT" else {
            throw ESMError.malformed("expected OTFT record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var items: [FormID] = []
        var skipped = FieldTally()
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "INAM":
                guard field.data.count % 4 == 0 else {
                    throw ESMError.malformed(
                        "OTFT \(formID) INAM has \(field.data.count) bytes, not a multiple of 4"
                    )
                }
                for _ in 0 ..< (field.data.count / 4) {
                    try items.append(FormID(reader.readUInt32()))
                }
            default:
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped
        self.editorID = editorID
        self.items = items
    }
}
