// REFR record decoded into engine types: base object FormID + placement.
// A REFR places one base record (STAT, TREE, DOOR, ...) at a world position.
// Per spec only NAME and DATA are required; everything else here is optional
// and the many activation/ownership fields are skipped for now.
//
// Reference: UESP "Skyrim Mod:Mod File Format/REFR"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REFR
// XTEL struct cross-check: xEdit dev-4.1.6 wbDefinitionsTES5.pas
//   https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
// Layout documented in docs/formats/records.md.

import Foundation
import simd

nonisolated struct PlacedReference {
    /// DATA field: 24 bytes, positions in game units, rotations in radians
    /// (Skyrim world axes — see docs/decisions/coordinates.md).
    struct Placement: Equatable {
        let position: SIMD3<Float>
        let rotation: SIMD3<Float>
    }

    /// XTEL field: destination door reference + arrival transform + flags.
    /// xEdit names the FormID target "Door" but constrains it to REFR.
    struct TeleportDestination: Equatable {
        struct Flags: OptionSet, Equatable {
            let rawValue: UInt32

            static let noAlarm = Flags(rawValue: 0x0000_0001)
        }

        let door: FormID
        let placement: Placement
        let flags: Flags
    }

    let formID: FormID
    /// NAME — the base object this reference places.
    let base: FormID
    let placement: Placement
    /// XSCL — uniform scale, defaulting to 1 when the field is absent.
    let scale: Float
    /// XTEL — present only on teleporting door references.
    let teleportDestination: TeleportDestination?
    /// XRDS — per-reference point-light radius override.
    let lightRadius: Float?
    /// XEMI — LIGH/REGN emittance override; LIGH handled by lighting pass.
    let emittance: FormID?

    init(record: ESMRecord) throws {
        guard record.type == "REFR" else {
            throw ESMError.malformed("expected REFR record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var base: FormID?
        var placement: Placement?
        var scale: Float = 1
        var teleportDestination: TeleportDestination?
        var lightRadius: Float?
        var emittance: FormID?
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
            case "XTEL":
                teleportDestination = try Self.decodeTeleport(field, reference: formID)
            case "XRDS":
                lightRadius = try Self.decodeFloat(field.data)
            case "XEMI":
                emittance = try Self.decodeFormID(field.data)
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
        self.teleportDestination = teleportDestination
        self.lightRadius = lightRadius
        self.emittance = emittance
    }

    private static func decodeFloat(_ data: Data) throws -> Float? {
        guard data.count >= 4 else { return nil }
        var reader = BinaryReader(data)
        return try reader.readFloat32()
    }

    private static func decodeFormID(_ data: Data) throws -> FormID? {
        guard data.count >= 4 else { return nil }
        var reader = BinaryReader(data)
        return try FormID(reader.readUInt32())
    }

    private static func decodeTeleport(
        _ field: ESMField,
        reference: FormID
    ) throws -> TeleportDestination {
        // UESP REFR + xEdit wbDefinitionsTES5.pas: exact 32-byte struct =
        // REFR FormID, position xyz, rotation xyz, uint32 flags.
        guard field.data.count == 32 else {
            throw ESMError.malformed(
                "REFR \(reference) XTEL has \(field.data.count) bytes, expected 32"
            )
        }
        var reader = BinaryReader(field.data)
        return try TeleportDestination(
            door: FormID(reader.readUInt32()),
            placement: Placement(
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
            ),
            flags: TeleportDestination.Flags(rawValue: reader.readUInt32())
        )
    }
}
