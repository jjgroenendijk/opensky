// ASPC acoustic space: links an interior cell to its ambient sound. Here RDAT
// is a 4-byte REGN FormID, not the 8-byte area header the REGN record uses.
// Layout and sources: docs/formats/acoustic-space.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct AcousticSpace: Sendable {
    public let formID: FormID
    public let editorID: String?
    /// SNAM -> SNDR. Direct ambient sound for any cell pointing at this
    /// acoustic space; nil when absent.
    public let ambientSound: FormID?
    /// RDAT -> REGN. Region whose type-7 sound area (RDSA entries) is borrowed
    /// to drive this interior's ambience. CK label: "Interiors Only". nil when
    /// absent; resolved through RegionStore by the audio director.
    public let borrowedRegion: FormID?
    /// BNAM -> REVB. Reverb / environment preset; decoded for completeness but
    /// unused until a reverb runtime exists. nil when absent.
    public let reverbModel: FormID?

    public init(record: ESMRecord) throws {
        guard record.type == "ASPC" else {
            throw ESMError.malformed("expected ASPC record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var ambientSound: FormID?
        var borrowedRegion: FormID?
        var reverbModel: FormID?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "SNAM":
                ambientSound = try Self.readOptionalFormID(
                    &reader, size: field.data.count
                )
            case "RDAT":
                borrowedRegion = try Self.readOptionalFormID(
                    &reader, size: field.data.count
                )
            case "BNAM":
                reverbModel = try Self.readOptionalFormID(
                    &reader, size: field.data.count
                )
            default:
                // OBND object bounds, plus any authoring-only fields, are
                // not consumed here.
                break
            }
        }
        self.editorID = editorID
        self.ambientSound = ambientSound
        self.borrowedRegion = borrowedRegion
        self.reverbModel = reverbModel
    }

    private static func readOptionalFormID(
        _ reader: inout BinaryReader,
        size: Int
    ) throws -> FormID? {
        guard size == 4 else { return nil }
        let formID = try FormID(reader.readUInt32())
        return formID.isNull ? nil : formID
    }
}
