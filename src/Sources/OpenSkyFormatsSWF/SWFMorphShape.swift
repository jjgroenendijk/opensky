// DefineMorphShape (46) and DefineMorphShape2 (84): a shape with a start and an end
// form that a placement's ratio blends. Layout and sources: docs/formats/swf-shapes.md.

import Foundation

/// A decoded morph shape. Each style and each edge comes as a start and an end
/// value at the same index; the edges keep the start edges' style indices.
nonisolated public struct SWFMorphShapeDefinition: Equatable, Sendable {
    public static let tagCodes: Set<UInt16> = [46, 84]

    public let characterId: UInt16
    public let startBounds: SWFRect
    public let endBounds: SWFRect
    /// DefineMorphShape2 only: the bounds without strokes.
    public let startEdgeBounds: SWFRect?
    public let endEdgeBounds: SWFRect?
    public let startFillStyles: [SWFFillStyle]
    public let endFillStyles: [SWFFillStyle]
    public let startLineStyles: [SWFLineStyle]
    public let endLineStyles: [SWFLineStyle]
    public let startSegments: [SWFShapeSegment]
    public let endSegments: [SWFShapeSegment]

    public static func parse(tag: SWFTag) throws -> SWFMorphShapeDefinition {
        guard tagCodes.contains(tag.code) else {
            throw SWFShapeError.unsupportedTag(tag.code)
        }
        let isVersion2 = tag.code == 84
        var bits = SWFBitReader(tag.body)
        let characterId = try bits.readAlignedUInt16()
        let startBounds = try SWFShapeParser.parseRect(&bits)
        let endBounds = try SWFShapeParser.parseRect(&bits)
        var startEdgeBounds: SWFRect?
        var endEdgeBounds: SWFRect?
        if isVersion2 {
            startEdgeBounds = try SWFShapeParser.parseRect(&bits)
            endEdgeBounds = try SWFShapeParser.parseRect(&bits)
            bits.align()
            _ = try bits.readUB(8) // Reserved UB[6], UsesNonScalingStrokes, UsesScalingStrokes
        }
        let offset = try Int(bits.readAlignedUInt32())
        let endEdgesStart = bits.byteOffset + offset
        let fills = try SWFMorphStyleParser.parseFillStyleArray(&bits)
        let lines = try SWFMorphStyleParser.parseLineStyleArray(&bits, isVersion2: isVersion2)
        let startSegments = try SWFShapeParser.parseGlyphShape(&bits)
        bits.align()
        if offset > 0, endEdgesStart < tag.body.count {
            bits = SWFBitReader(tag.body)
            bits.advance(byteCount: endEdgesStart)
        }
        let endSegments = try SWFShapeParser.parseGlyphShape(&bits)
        guard startSegments.count == endSegments.count else {
            throw SWFShapeError.morphEdgeCountMismatch(
                start: startSegments.count, end: endSegments.count
            )
        }
        return SWFMorphShapeDefinition(
            characterId: characterId,
            startBounds: startBounds,
            endBounds: endBounds,
            startEdgeBounds: startEdgeBounds,
            endEdgeBounds: endEdgeBounds,
            startFillStyles: fills.map(\.start),
            endFillStyles: fills.map(\.end),
            startLineStyles: lines.map(\.start),
            endLineStyles: lines.map(\.end),
            startSegments: startSegments,
            endSegments: endSegments
        )
    }
}

/// MORPHFILLSTYLE and MORPHLINESTYLE(2): each record holds a start and an end value.
nonisolated enum SWFMorphStyleParser {
    typealias Pair<Value> = (start: Value, end: Value)

    /// MORPHFILLSTYLEARRAY: UI8 count, 0xFF escapes to a UI16 count.
    static func parseFillStyleArray(_ bits: inout SWFBitReader) throws -> [Pair<SWFFillStyle>] {
        let count = try styleCount(&bits)
        var styles: [Pair<SWFFillStyle>] = []
        styles.reserveCapacity(min(count, 256))
        for _ in 0 ..< count {
            try styles.append(parseFillStyle(&bits))
        }
        return styles
    }

    static func parseLineStyleArray(
        _ bits: inout SWFBitReader,
        isVersion2: Bool
    ) throws -> [Pair<SWFLineStyle>] {
        let count = try styleCount(&bits)
        var styles: [Pair<SWFLineStyle>] = []
        styles.reserveCapacity(min(count, 256))
        for _ in 0 ..< count {
            if isVersion2 {
                try styles.append(parseLineStyle2(&bits))
            } else {
                let startWidth = try bits.readAlignedUInt16()
                let endWidth = try bits.readAlignedUInt16()
                let startColor = try SWFShapeParser.parseColor(&bits, hasAlpha: true)
                let endColor = try SWFShapeParser.parseColor(&bits, hasAlpha: true)
                styles.append((
                    SWFLineStyle(width: startWidth, color: startColor),
                    SWFLineStyle(width: endWidth, color: endColor)
                ))
            }
        }
        return styles
    }

    static func parseFillStyle(_ bits: inout SWFBitReader) throws -> Pair<SWFFillStyle> {
        let type = try bits.readAlignedUInt8()
        switch type {
        case 0x00:
            let start = try SWFShapeParser.parseColor(&bits, hasAlpha: true)
            let end = try SWFShapeParser.parseColor(&bits, hasAlpha: true)
            return (.solid(start), .solid(end))
        case 0x10, 0x12, 0x13:
            let startMatrix = try SWFShapeParser.parseMatrix(&bits)
            let endMatrix = try SWFShapeParser.parseMatrix(&bits)
            let gradients = try parseGradient(&bits, isFocal: type == 0x13)
            func style(_ matrix: SWFMatrix, _ gradient: SWFGradient) -> SWFFillStyle {
                switch type {
                case 0x10: .linearGradient(matrix: matrix, gradient: gradient)
                case 0x12: .radialGradient(matrix: matrix, gradient: gradient)
                default: .focalRadialGradient(matrix: matrix, gradient: gradient)
                }
            }
            return (style(startMatrix, gradients.start), style(endMatrix, gradients.end))
        case 0x40, 0x41, 0x42, 0x43:
            let bitmapId = try bits.readAlignedUInt16()
            let startMatrix = try SWFShapeParser.parseMatrix(&bits)
            let endMatrix = try SWFShapeParser.parseMatrix(&bits)
            func style(_ matrix: SWFMatrix) -> SWFFillStyle {
                .bitmap(
                    characterId: bitmapId, matrix: matrix,
                    tiled: type & 0x01 == 0, smoothed: type < 0x42
                )
            }
            return (style(startMatrix), style(endMatrix))
        default:
            throw SWFShapeError.invalidFillStyleType(type)
        }
    }

    /// MORPHGRADIENT. The count byte is read as GRADIENT packs it, so the spread and
    /// interpolation bits are kept; a focal fill adds a start and an end focal point.
    static func parseGradient(
        _ bits: inout SWFBitReader,
        isFocal: Bool
    ) throws -> Pair<SWFGradient> {
        bits.align()
        let spread = try SWFGradient.SpreadMode(rawValue: UInt8(bits.readUB(2))) ?? .reserved
        let interpolation = try SWFGradient.InterpolationMode(
            rawValue: UInt8(bits.readUB(2))
        ) ?? .reserved3
        let count = try Int(bits.readUB(4))
        var start: [SWFGradientRecord] = []
        var end: [SWFGradientRecord] = []
        for _ in 0 ..< count {
            let startRatio = try bits.readAlignedUInt8()
            let startColor = try SWFShapeParser.parseColor(&bits, hasAlpha: true)
            let endRatio = try bits.readAlignedUInt8()
            let endColor = try SWFShapeParser.parseColor(&bits, hasAlpha: true)
            start.append(SWFGradientRecord(ratio: startRatio, color: startColor))
            end.append(SWFGradientRecord(ratio: endRatio, color: endColor))
        }
        var startFocal: Float?
        var endFocal: Float?
        if isFocal {
            startFocal = try Float(Int16(bitPattern: bits.readAlignedUInt16())) / 256
            endFocal = try Float(Int16(bitPattern: bits.readAlignedUInt16())) / 256
        }
        func gradient(_ records: [SWFGradientRecord], _ focal: Float?) -> SWFGradient {
            SWFGradient(
                spreadMode: spread, interpolationMode: interpolation,
                records: records, focalPoint: focal
            )
        }
        return (gradient(start, startFocal), gradient(end, endFocal))
    }

    /// MORPHLINESTYLE2: two widths, the LINESTYLE2 flags, then two colours or a
    /// morph fill.
    static func parseLineStyle2(_ bits: inout SWFBitReader) throws -> Pair<SWFLineStyle> {
        let startWidth = try bits.readAlignedUInt16()
        let endWidth = try bits.readAlignedUInt16()
        // The LINESTYLE2 flag bits, most significant first: start cap, join, fill,
        // no horizontal and vertical scale, pixel hinting, 5 reserved, no close, end cap.
        let flags = try bits.readUB(16)
        let joinRaw = (flags >> 12) & 0x03
        var join: SWFLineStyle.JoinStyle = joinRaw == 1 ? .bevel : .round
        if joinRaw == 2 {
            join = try .miter(limitFactor: Float(bits.readAlignedUInt16()) / 256)
        }
        let black = SWFColor(red: 0, green: 0, blue: 0, alpha: 255)
        var start = SWFLineStyle(width: startWidth, color: black)
        var end = SWFLineStyle(width: endWidth, color: black)
        if flags & 0x0800 != 0 {
            let fill = try parseFillStyle(&bits)
            start.fill = fill.start
            end.fill = fill.end
        } else {
            start.color = try SWFShapeParser.parseColor(&bits, hasAlpha: true)
            end.color = try SWFShapeParser.parseColor(&bits, hasAlpha: true)
        }
        apply(flags: flags, join: join, to: &start)
        apply(flags: flags, join: join, to: &end)
        return (start, end)
    }

    private static func apply(
        flags: UInt32, join: SWFLineStyle.JoinStyle, to style: inout SWFLineStyle
    ) {
        style.startCap = SWFLineStyle.CapStyle(rawValue: UInt8(flags >> 14 & 0x03)) ?? .round
        style.endCap = SWFLineStyle.CapStyle(rawValue: UInt8(flags & 0x03)) ?? .round
        style.join = join
        style.noHScale = flags & 0x0400 != 0
        style.noVScale = flags & 0x0200 != 0
        style.pixelHinting = flags & 0x0100 != 0
        style.noClose = flags & 0x0004 != 0
    }

    private static func styleCount(_ bits: inout SWFBitReader) throws -> Int {
        let count = try Int(bits.readAlignedUInt8())
        return count == 0xFF ? try Int(bits.readAlignedUInt16()) : count
    }
}
