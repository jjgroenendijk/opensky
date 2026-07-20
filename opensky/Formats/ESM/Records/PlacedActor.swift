// ACHR record decoded into engine types: base actor FormID + placement.
// An ACHR places one NPC_ base actor at a world position; the field shape
// mirrors REFR (NAME base, DATA pos/rot, XSCL scale) and lives in the same
// cell persistent/temporary children groups. Editor-placement and script
// fields are skipped for the bind-pose milestone.
//
// Reference: UESP "Skyrim Mod:Mod File Format/ACHR"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ACHR
// Layout documented in docs/formats/actors.md.

import Foundation
import simd

nonisolated struct PlacedActor {
    let formID: FormID
    /// NAME — the NPC_ base actor this reference places.
    let base: FormID
    let placement: PlacedReference.Placement
    /// XSCL — uniform scale, defaulting to 1 when the field is absent.
    let scale: Float
    /// Record-header flag 0x800 (UESP): the actor stays hidden until a quest
    /// or script enables it. M5 has no script state -> explicit render skip.
    let isInitiallyDisabled: Bool

    init(record: ESMRecord) throws {
        guard record.type == "ACHR" else {
            throw ESMError.malformed("expected ACHR record, got \(record.type)")
        }
        formID = FormID(record.formID)
        isInitiallyDisabled = record.isInitiallyDisabled

        var base: FormID?
        var placement: PlacedReference.Placement?
        var scale: Float = 1
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "NAME":
                base = try FormID(reader.readUInt32())
            case "DATA":
                placement = try PlacedReference.Placement(
                    position: SIMD3(
                        Float(bitPattern: reader.readUInt32()),
                        Float(bitPattern: reader.readUInt32()),
                        Float(bitPattern: reader.readUInt32())
                    ),
                    rotation: SIMD3(
                        Float(bitPattern: reader.readUInt32()),
                        Float(bitPattern: reader.readUInt32()),
                        Float(bitPattern: reader.readUInt32())
                    )
                )
            case "XSCL":
                scale = try Float(bitPattern: reader.readUInt32())
            default:
                break
            }
        }
        guard let base else {
            throw ESMError.malformed("ACHR \(formID) has no NAME field")
        }
        guard let placement else {
            throw ESMError.malformed("ACHR \(formID) has no DATA field")
        }
        self.base = base
        self.placement = placement
        self.scale = scale
    }
}
