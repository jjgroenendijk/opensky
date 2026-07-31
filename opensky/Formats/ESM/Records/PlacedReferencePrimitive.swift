// XPRM (primitive volume) decode for REFR, split out of PlacedReference.swift
// to keep that type under the SwiftLint type-body limit.
//
// Reference: UESP "Skyrim Mod:Mod File Format/REFR" XPRM row
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REFR
// Struct cross-check: xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas line 9701
//   `wbStruct(XPRM, 'Primitive', [wbStruct('Bounds', ...), wbFloatRGBA,
//   wbInteger('Type', itU32, wbEnum([...]))])`
// Layout documented in docs/formats/records.md.

import Foundation
import simd

extension PlacedReference {
    /// XPRM field: the invisible volume a reference encloses. Trigger boxes,
    /// activation volumes, portal boxes and occlusion volumes all carry one.
    nonisolated struct Primitive: Equatable, Sendable {
        /// Half-extents in native Skyrim world units, pre-scale — the stored
        /// values are half the volume's size along each axis, which is why
        /// UESP labels the row "Bounds / 2" and xEdit displays it with a
        /// float scale of 2. XSCL still multiplies them at placement time.
        let halfExtents: SIMD3<Float>
        /// Editor wireframe color, stored 0...1 (UESP: "Color / 255"). Not
        /// rendered in game; kept because it distinguishes volume roles in
        /// the Creation Kit and costs nothing to carry.
        let color: SIMD3<Float>
        /// Fourth `wbFloatRGBA` member, named "Alpha" by xEdit and left
        /// unknown by UESP. Preserved verbatim rather than interpreted; see
        /// the flagged uncertainty in docs/formats/records.md.
        let unknown: Float
        /// Volume shape. `halfExtents` reads as a box's half-size for `.box`
        /// and `.portalBox`, and as a radius triple for `.sphere`.
        let type: PrimitiveType
    }

    /// XPRM trailing uint32. Names follow xEdit's `wbEnum`; UESP lists the
    /// same range but leaves 4 unnamed.
    nonisolated enum PrimitiveType: UInt32, Equatable, Sendable {
        case none = 0
        case box = 1
        case sphere = 2
        case portalBox = 3
        case line = 4
    }

    /// Decodes the single XPRM payload on a reference.
    ///
    /// Size policy follows XTEL rather than XLKR: XPRM is one non-repeating
    /// struct whose fields are all fixed-width, so a payload of the wrong
    /// length can only be read by shifting every field. A shifted read gives
    /// a trigger volume the wrong size and the wrong shape, which is worse
    /// than the caller logging and skipping the reference, so any length
    /// other than 32 throws.
    ///
    /// An unrecognised `type` throws for the same reason. xEdit's enumeration
    /// is closed (0...4) and Skyrim.esm stays inside it — 10163 boxes, 137
    /// spheres, 3135 portal boxes, 233 lines, no `none` — so a value outside
    /// the range means the payload is not a primitive this decoder
    /// understands; guessing `.box` for it would place a solid-looking volume
    /// of unknown shape. The cost is bounded: only the reference carrying the
    /// bad field is lost, and vanilla data contains none.
    ///
    /// Layout, UESP REFR + xEdit wbDefinitionsTES5.pas: exact 32-byte struct =
    /// bounds xyz, color rgb, unknown float (xEdit "Alpha"), uint32 type.
    nonisolated static func decodePrimitive(
        _ field: ESMField,
        reference: FormID
    ) throws -> Primitive {
        guard field.data.count == 32 else {
            throw ESMError.malformed(
                "REFR \(reference) XPRM has \(field.data.count) bytes, expected 32"
            )
        }
        var reader = BinaryReader(field.data)
        let halfExtents = try SIMD3<Float>(
            Float(bitPattern: reader.readUInt32()),
            Float(bitPattern: reader.readUInt32()),
            Float(bitPattern: reader.readUInt32())
        )
        let color = try SIMD3<Float>(
            Float(bitPattern: reader.readUInt32()),
            Float(bitPattern: reader.readUInt32()),
            Float(bitPattern: reader.readUInt32())
        )
        let unknown = try Float(bitPattern: reader.readUInt32())
        let rawType = try reader.readUInt32()
        guard let type = PrimitiveType(rawValue: rawType) else {
            throw ESMError.malformed("REFR \(reference) XPRM has unknown type \(rawType)")
        }
        return Primitive(halfExtents: halfExtents, color: color, unknown: unknown, type: type)
    }
}
