// PlaceObject3 FILTERLIST: drop shadow, glow, and blur keep their values; the other kinds
// keep only their FilterID. Layout: docs/formats/swf-display-list.md#filters.

import Foundation

/// A drop shadow or a glow. A glow is a shadow with no distance.
nonisolated public struct SWFShadowFilter: Equatable, Sendable {
    public var color: SWFColor
    /// Blur radii and distance in pixels; angle in radians, 0 along +x, turning to +y.
    public var blurX: Float = 0
    public var blurY: Float = 0
    public var angle: Float = 0
    public var distance: Float = 0
    public var strength: Float = 1
    public var isInner = false
    public var isKnockout = false
    /// False hides the object itself, so only its shadow draws.
    public var drawsSource = true
    public var isGlow = false

    public init(color: SWFColor) {
        self.color = color
    }
}

nonisolated public enum SWFFilter: Equatable, Sendable {
    case shadow(SWFShadowFilter)
    case blur(x: Float, y: Float)
    /// A kind OpenSky does not draw, by its FilterID.
    case other(id: UInt8)

    static let dropShadowID: UInt8 = 0
    static let blurID: UInt8 = 1
    static let glowID: UInt8 = 2

    /// The FilterID the tag stored.
    public var id: UInt8 {
        switch self {
        case let .shadow(shadow): shadow.isGlow ? Self.glowID : Self.dropShadowID
        case .blur: Self.blurID
        case let .other(id): id
        }
    }

    /// Reads a FILTERLIST (spec PlaceObject3, pp. 40-48).
    static func parseList(_ bits: inout SWFBitReader) throws -> [SWFFilter] {
        let count = try Int(bits.readAlignedUInt8())
        return try (0 ..< count).map { _ in try parse(&bits) }
    }

    private static func parse(_ bits: inout SWFBitReader) throws -> SWFFilter {
        let filterID = try bits.readAlignedUInt8()
        switch filterID {
        case dropShadowID:
            var shadow = try SWFShadowFilter(color: SWFShapeParser.parseColor(
                &bits,
                hasAlpha: true
            ))
            shadow.blurX = try fixed(&bits)
            shadow.blurY = try fixed(&bits)
            shadow.angle = try fixed(&bits)
            shadow.distance = try fixed(&bits)
            try readStrengthAndFlags(into: &shadow, &bits)
            return .shadow(shadow)
        case blurID:
            let blurX = try fixed(&bits), blurY = try fixed(&bits)
            _ = try bits.readAlignedUInt8() // Passes UB[5], Reserved UB[3]
            return .blur(x: blurX, y: blurY)
        case glowID:
            var glow = try SWFShadowFilter(color: SWFShapeParser.parseColor(&bits, hasAlpha: true))
            glow.blurX = try fixed(&bits)
            glow.blurY = try fixed(&bits)
            glow.isGlow = true
            try readStrengthAndFlags(into: &glow, &bits)
            return .shadow(glow)
        default:
            try skip(filterID, &bits)
            return .other(id: filterID)
        }
    }

    /// The strength and the flag byte both shadow kinds end with.
    private static func readStrengthAndFlags(
        into shadow: inout SWFShadowFilter, _ bits: inout SWFBitReader
    ) throws {
        shadow.strength = try Float(Int16(bitPattern: bits.readAlignedUInt16())) / 256
        let flags = try bits.readAlignedUInt8()
        shadow.isInner = flags & 0x80 != 0
        shadow.isKnockout = flags & 0x40 != 0
        shadow.drawsSource = flags & 0x20 != 0
    }

    /// FIXED: a signed 16.16 number, low half first.
    private static func fixed(_ bits: inout SWFBitReader) throws -> Float {
        let low = try UInt32(bits.readAlignedUInt16())
        let high = try UInt32(bits.readAlignedUInt16())
        return Float(Int32(bitPattern: high << 16 | low)) / 65536
    }

    private static func skip(_ filterID: UInt8, _ bits: inout SWFBitReader) throws {
        let size: Int
        switch filterID {
        case 3: size = 27 // Bevel
        case 4, 7: // GradientGlow and GradientBevel: NumColors, then 5 bytes a colour
            size = try Int(bits.readAlignedUInt8()) * 5 + 19
        case 5: // Convolution: MatrixX, MatrixY, then a FLOAT each, then a fixed tail
            let matrixX = try Int(bits.readAlignedUInt8())
            let matrixY = try Int(bits.readAlignedUInt8())
            size = 4 + 4 + matrixX * matrixY * 4 + 4 + 1
        case 6: size = 80 // ColorMatrix: 20 FLOATs
        default: throw SWFDisplayListError.unknownFilterID(filterID)
        }
        bits.align()
        guard bits.remainingData.count >= size else {
            throw SWFBitReaderError.outOfBounds(
                bitsRequested: size * 8, bitsRemaining: bits.remainingData.count * 8
            )
        }
        bits.advance(byteCount: size)
    }
}
