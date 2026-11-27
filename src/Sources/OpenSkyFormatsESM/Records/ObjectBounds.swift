// OBND bounding box: six int16 in the order X1 Y1 Z1 X2 Y2 Z2, minimum corner
// then maximum, relative to the record origin. Shared by most base records.
// Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct ObjectBounds: Equatable, Sendable {
    /// Minimum corner (X1, Y1, Z1) in game units.
    public let minimum: SIMD3<Int16>
    /// Maximum corner (X2, Y2, Z2) in game units.
    public let maximum: SIMD3<Int16>

    /// True when every component is zero — the "no meaningful bounds" case
    /// vanilla writes for records whose volume the engine never queries.
    public var isEmpty: Bool {
        minimum == .zero && maximum == .zero
    }

    /// Half the box's diagonal: the size a dropped item needs.
    public var radius3D: Float {
        0.5 * simd_length(extent)
    }

    /// Half the box's floor diagonal: the room a summoned actor needs.
    public var radius2D: Float {
        0.5 * simd_length(SIMD2(extent.x, extent.y))
    }

    private var extent: SIMD3<Float> {
        SIMD3<Float>(maximum) - SIMD3<Float>(minimum)
    }

    public init(minimum: SIMD3<Int16>, maximum: SIMD3<Int16>) {
        self.minimum = minimum
        self.maximum = maximum
    }

    /// Decodes an OBND payload. A field shorter than 12 bytes is structurally
    /// unusable, so it throws rather than inventing a box; callers that would
    /// rather skip the record catch and continue per the mod-quirk rule.
    public init(field: ESMField) throws {
        guard field.data.count >= 12 else {
            throw ESMError.malformed(
                "OBND has \(field.data.count) bytes, expected 12"
            )
        }
        var reader = BinaryReader(field.data)
        minimum = try SIMD3(
            Int16(bitPattern: reader.readUInt16()),
            Int16(bitPattern: reader.readUInt16()),
            Int16(bitPattern: reader.readUInt16())
        )
        maximum = try SIMD3(
            Int16(bitPattern: reader.readUInt16()),
            Int16(bitPattern: reader.readUInt16()),
            Int16(bitPattern: reader.readUInt16())
        )
    }
}
