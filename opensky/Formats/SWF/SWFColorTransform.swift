// CXFORM / CXFORMWITHALPHA record decoding plus the color-transform algebra
// the display-list renderer applies per draw (multiply then add, clamped).
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 1 —
// "Color transform record" / "Color transform with alpha record" (pp. 24-25).
// Layout: HasAddTerms UB[1], HasMultTerms UB[1], Nbits UB[4], then the
// multiply terms (R, G, B[, A] as SB[Nbits], 8.8 fixed point) followed by the
// add terms (R, G, B[, A] as SB[Nbits], integer -255..255). Like RECT and
// MATRIX, the record is byte aligned.

import Foundation
import simd

/// A decoded color transform in the straight-alpha 0..1 domain:
/// `result = clamp(color * multiply + add, 0, 1)`. Multiply terms decode from
/// 8.8 fixed point (stored value / 256); add terms decode from the -255..255
/// integer domain (stored value / 255).
nonisolated struct SWFColorTransform: Equatable {
    var multiply = SIMD4<Float>(repeating: 1)
    var add = SIMD4<Float>(repeating: 0)

    static let identity = SWFColorTransform()

    var isIdentity: Bool {
        self == .identity
    }

    /// Decodes a CXFORM (`hasAlpha == false`, alpha terms untouched) or
    /// CXFORMWITHALPHA record at the reader's position.
    static func parse(_ bits: inout SWFBitReader, hasAlpha: Bool) throws -> SWFColorTransform {
        bits.align()
        let hasAdd = try bits.readUB(1) == 1
        let hasMultiply = try bits.readUB(1) == 1
        let nbits = try Int(bits.readUB(4))
        var transform = SWFColorTransform()
        let channels = hasAlpha ? 4 : 3
        if hasMultiply {
            for channel in 0 ..< channels {
                transform.multiply[channel] = try Float(bits.readSB(nbits)) / 256
            }
        }
        if hasAdd {
            for channel in 0 ..< channels {
                transform.add[channel] = try Float(bits.readSB(nbits)) / 255
            }
        }
        return transform
    }

    /// Applies `self` to a straight-alpha color.
    func apply(to color: SIMD4<Float>) -> SIMD4<Float> {
        simd_clamp(color * multiply + add, SIMD4(repeating: 0), SIMD4(repeating: 1))
    }

    /// The transform equivalent to applying `inner` first, then `self` — the
    /// order a parent timeline wraps a child placement.
    func concatenating(_ inner: SWFColorTransform) -> SWFColorTransform {
        SWFColorTransform(
            multiply: multiply * inner.multiply,
            add: multiply * inner.add + add
        )
    }
}
