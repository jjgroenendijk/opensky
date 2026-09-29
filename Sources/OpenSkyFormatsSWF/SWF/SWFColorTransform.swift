// CXFORM and CXFORMWITHALPHA decoding plus the per-draw color math: multiply,
// then add, then clamp. Multiply terms are 8.8 fixed point, add terms integers;
// the record is byte aligned (SWF spec v19, pp. 24-25).

import Foundation
import simd

/// A decoded color transform in the straight-alpha 0..1 domain:
/// `result = clamp(color * multiply + add, 0, 1)`. Multiply terms decode from
/// 8.8 fixed point (stored value / 256); add terms decode from the -255..255
/// integer domain (stored value / 255).
nonisolated public struct SWFColorTransform: Equatable, Sendable {
    public var multiply = SIMD4<Float>(repeating: 1)
    public var add = SIMD4<Float>(repeating: 0)

    public static let identity = SWFColorTransform()

    /// Decodes a CXFORM (`hasAlpha == false`, alpha terms untouched) or
    /// CXFORMWITHALPHA record at the reader's position.
    public static func parse(
        _ bits: inout SWFBitReader,
        hasAlpha: Bool
    ) throws -> SWFColorTransform {
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
    public func apply(to color: SIMD4<Float>) -> SIMD4<Float> {
        simd_clamp(color * multiply + add, SIMD4(repeating: 0), SIMD4(repeating: 1))
    }

    /// The transform equivalent to applying `inner` first, then `self` — the
    /// order a parent timeline wraps a child placement.
    public func concatenating(_ inner: SWFColorTransform) -> SWFColorTransform {
        SWFColorTransform(
            multiply: multiply * inner.multiply,
            add: multiply * inner.add + add
        )
    }
}
