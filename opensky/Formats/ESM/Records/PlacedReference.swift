// REFR record decoded into engine types: base object FormID + placement.
// A REFR places one base record (STAT, TREE, DOOR, ...) at a world position.
// Per spec only NAME and DATA are required; everything else here is optional
// and the many activation/ownership fields are skipped for now.
//
// Reference: UESP "Skyrim Mod:Mod File Format/REFR"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REFR
// Layout documented in docs/formats/records.md.

import Foundation
import simd

nonisolated struct PlacedReference {
    /// DATA field: 24 bytes, positions in game units, rotations in radians
    /// (Skyrim world axes — see docs/decisions on coordinates, milestone 2).
    struct Placement: Equatable {
        let position: SIMD3<Float>
        let rotation: SIMD3<Float>
    }

    let formID: FormID
    /// NAME — the base object this reference places.
    let base: FormID
    let placement: Placement
    /// XSCL — uniform scale, defaulting to 1 when the field is absent.
    let scale: Float

    init(record: ESMRecord) throws {
        guard record.type == "REFR" else {
            throw ESMError.malformed("expected REFR record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var base: FormID?
        var placement: Placement?
        var scale: Float = 1
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "NAME":
                base = try FormID(reader.readUInt32())
            case "DATA":
                placement = try Placement(
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
            throw ESMError.malformed("REFR \(formID) has no NAME field")
        }
        guard let placement else {
            throw ESMError.malformed("REFR \(formID) has no DATA field")
        }
        self.base = base
        self.placement = placement
        self.scale = scale
    }
}
