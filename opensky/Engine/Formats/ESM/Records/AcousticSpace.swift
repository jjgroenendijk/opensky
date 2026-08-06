// ASPC acoustic-space record (M9.2.2). The bridge between an interior cell
// and its ambient sound bed: CELL.XCAS -> ASPC.SNAM plays directly, and
// ASPC.RDAT optionally borrows a REGN's type-7 sound area to drive this
// interior's ambience (CK label: "Use Sound from Region (Interiors Only)").
//
// Reference: UESP "Skyrim Mod:Mod File Format/ASPC"; xEdit dev-4.1.6
// wbDefinitionsTES5.pas lines 5401-5407:
//   wbRecord(ASPC, 'Acoustic Space', [
//     wbEDID, wbOBND(True),
//     wbFormIDCk(SNAM, 'Ambient Sound',            [SNDR]),
//     wbFormIDCk(RDAT, 'Use Sound from Region (Interiors Only)', [REGN]),
//     wbFormIDCk(BNAM, 'Environment Type (reverb)', [REVB])
//   ]);
//
// Field-name collision: ASPC.RDAT here is a 4-byte REGN FormID, NOT the
// 8-byte area header the REGN record itself uses (Region.swift). Same FourCC,
// different layout and target. This decoder treats RDAT as a plain FormID.

import Foundation

nonisolated struct AcousticSpace {
    let formID: FormID
    let editorID: String?
    /// SNAM -> SNDR. Direct ambient sound for any cell pointing at this
    /// acoustic space; nil when absent.
    let ambientSound: FormID?
    /// RDAT -> REGN. Region whose type-7 sound area (RDSA entries) is borrowed
    /// to drive this interior's ambience. CK label: "Interiors Only". nil when
    /// absent; resolved through RegionStore by the audio director.
    let borrowedRegion: FormID?
    /// BNAM -> REVB. Reverb / environment preset; decoded for completeness but
    /// unused until a reverb runtime exists. nil when absent.
    let reverbModel: FormID?

    init(record: ESMRecord) throws {
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
