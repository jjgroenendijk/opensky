// Where a placed reference's `XEMI` emittance colour comes from
// (docs/formats/nif-materials.md#effect-shapes).

import simd

nonisolated public enum EmittanceSource: Hashable, Sendable {
    /// A light's colour, which stays fixed.
    case light(SIMD3<Float>)
    /// A region's weather `Effect Lighting` colour, which follows the time of day.
    case region(UInt32)

    public var region: UInt32? {
        if case let .region(id) = self {
            id
        } else {
            nil
        }
    }

    /// The emittance as an instance colour: alpha 1 when a colour is known, else white with
    /// alpha 0, so the shader falls back to the scene light.
    public static func colour(
        of source: EmittanceSource?, regions: [UInt32: SIMD3<Float>]
    ) -> SIMD4<Float> {
        switch source {
        case let .light(colour): SIMD4(colour, 1)
        case let .region(id): regions[id].map { SIMD4($0, 1) } ?? SIMD4(1, 1, 1, 0)
        case nil: SIMD4(1, 1, 1, 0)
        }
    }
}
