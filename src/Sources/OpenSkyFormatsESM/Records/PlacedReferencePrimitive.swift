// XPRM primitive volume decode for REFR, in its own file for the type-body
// limit. Layout and sources: docs/formats/placed-references.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated extension PlacedReference {
    /// XPRM field: the invisible volume a reference encloses. Trigger boxes,
    /// activation volumes, portal boxes and occlusion volumes all carry one.
    nonisolated public struct Primitive: Equatable, Sendable {
        /// Half-extents in native Skyrim world units, pre-scale — the stored
        /// values are half the volume's size along each axis, which is why
        /// UESP labels the row "Bounds / 2" and xEdit displays it with a
        /// float scale of 2. XSCL still multiplies them at placement time.
        public let halfExtents: SIMD3<Float>
        /// Editor wireframe color, stored 0...1 (UESP: "Color / 255"). Not
        /// rendered in game; kept because it distinguishes volume roles in
        /// the Creation Kit and costs nothing to carry.
        public let color: SIMD3<Float>
        /// Fourth `wbFloatRGBA` member, named "Alpha" by xEdit and left
        /// unknown by UESP. Preserved verbatim rather than interpreted; see
        /// the flagged uncertainty in docs/formats/placed-references.md.
        public let unknown: Float
        /// Volume shape. `halfExtents` reads as a box's half-size for `.box`
        /// and `.portalBox`, and as a radius triple for `.sphere`.
        public let type: PrimitiveType
    }

    /// XPRM trailing uint32. Names follow xEdit's `wbEnum`; UESP lists the
    /// same range but leaves 4 unnamed.
    nonisolated public enum PrimitiveType: UInt32, Equatable, Sendable {
        case none = 0
        case box = 1
        case sphere = 2
        case portalBox = 3
        case line = 4
    }

    /// Decodes the XPRM payload. A length other than 32 or a type outside 0...4
    /// throws, because a guessed volume would have the wrong size or shape.
    /// Only that one reference is lost. Layout: docs/formats/placed-references.md.
    nonisolated public static func decodePrimitive(
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
