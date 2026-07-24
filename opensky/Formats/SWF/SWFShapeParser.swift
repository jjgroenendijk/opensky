// Bit-level decoding of SWF shape structures: RECT, MATRIX, GRADIENT,
// FILLSTYLEARRAY / LINESTYLEARRAY, and the SHAPE record stream
// (style-change / straight-edge / curved-edge records).
//
// Reference: Adobe SWF File Format Specification, version 19 — chapter 1
// "Rectangle record" / "MATRIX record" (pp. 22-23), chapter 6 "Shape
// structures" (pp. 121-131), chapter 7 "Gradient structures" (pp. 135-136).
// Alignment notes: RECT and MATRIX "must be byte aligned" per the spec. The
// spec does not state alignment for GRADIENT or for the NumFillBits field
// after the style arrays; observed encoders byte-align both (every vanilla
// Interface movie parses under this rule — see docs/formats/swf.md).

import Foundation

nonisolated enum SWFShapeParser {
    /// SHAPEWITHSTYLE decode output: flattened style lists plus segments.
    struct ShapeContents {
        let fillStyles: [SWFFillStyle]
        let lineStyles: [SWFLineStyle]
        let segments: [SWFShapeSegment]
    }

    /// RECT: `Nbits = UB[5]`, then four SB[Nbits] twip fields. Byte-aligned.
    static func parseRect(_ bits: inout SWFBitReader) throws -> SWFRect {
        bits.align()
        let nbits = try Int(bits.readUB(5))
        return try SWFRect(
            xMin: bits.readSB(nbits),
            xMax: bits.readSB(nbits),
            yMin: bits.readSB(nbits),
            yMax: bits.readSB(nbits)
        )
    }

    /// MATRIX: optional 16.16 fixed scale pair, optional 16.16 rotate/skew
    /// pair, then twip translation. Byte-aligned.
    static func parseMatrix(_ bits: inout SWFBitReader) throws -> SWFMatrix {
        bits.align()
        var matrix = SWFMatrix.identity
        if try bits.readUB(1) == 1 {
            let scaleBits = try Int(bits.readUB(5))
            matrix.scaleX = try Float(bits.readSB(scaleBits)) / 65536
            matrix.scaleY = try Float(bits.readSB(scaleBits)) / 65536
        }
        if try bits.readUB(1) == 1 {
            let rotateBits = try Int(bits.readUB(5))
            matrix.rotateSkew0 = try Float(bits.readSB(rotateBits)) / 65536
            matrix.rotateSkew1 = try Float(bits.readSB(rotateBits)) / 65536
        }
        let translateBits = try Int(bits.readUB(5))
        matrix.translateX = try bits.readSB(translateBits)
        matrix.translateY = try bits.readSB(translateBits)
        return matrix
    }

    /// RGB (3 bytes) or RGBA (4 bytes) color record; RGB parses as opaque.
    static func parseColor(_ bits: inout SWFBitReader, hasAlpha: Bool) throws -> SWFColor {
        bits.align()
        return try SWFColor(
            red: UInt8(bits.readUB(8)),
            green: UInt8(bits.readUB(8)),
            blue: UInt8(bits.readUB(8)),
            alpha: hasAlpha ? UInt8(bits.readUB(8)) : 255
        )
    }

    /// GRADIENT / FOCALGRADIENT: spread UB[2], interpolation UB[2],
    /// NumGradients UB[4], GRADRECORDs, then FIXED8 focal point when focal.
    static func parseGradient(
        _ bits: inout SWFBitReader,
        version: SWFShapeVersion,
        isFocal: Bool
    ) throws -> SWFGradient {
        bits.align()
        let spread = try SWFGradient.SpreadMode(rawValue: UInt8(bits.readUB(2))) ?? .reserved
        let interpolation = try SWFGradient.InterpolationMode(
            rawValue: UInt8(bits.readUB(2))
        ) ?? .reserved3
        let count = try Int(bits.readUB(4))
        var records: [SWFGradientRecord] = []
        records.reserveCapacity(count)
        for _ in 0 ..< count {
            let ratio = try bits.readAlignedUInt8()
            let color = try parseColor(&bits, hasAlpha: version.hasAlphaColors)
            records.append(SWFGradientRecord(ratio: ratio, color: color))
        }
        var focalPoint: Float?
        if isFocal {
            // FIXED8: signed 8.8 fixed point, little-endian.
            focalPoint = try Float(Int16(bitPattern: bits.readAlignedUInt16())) / 256
        }
        return SWFGradient(
            spreadMode: spread,
            interpolationMode: interpolation,
            records: records,
            focalPoint: focalPoint
        )
    }

    /// One FILLSTYLE, dispatched on the FillStyleType byte.
    static func parseFillStyle(
        _ bits: inout SWFBitReader,
        version: SWFShapeVersion
    ) throws -> SWFFillStyle {
        let type = try bits.readAlignedUInt8()
        switch type {
        case 0x00:
            return try .solid(parseColor(&bits, hasAlpha: version.hasAlphaColors))
        case 0x10, 0x12, 0x13:
            let matrix = try parseMatrix(&bits)
            let gradient = try parseGradient(&bits, version: version, isFocal: type == 0x13)
            return switch type {
            case 0x10: .linearGradient(matrix: matrix, gradient: gradient)
            case 0x12: .radialGradient(matrix: matrix, gradient: gradient)
            default: .focalRadialGradient(matrix: matrix, gradient: gradient)
            }
        case 0x40, 0x41, 0x42, 0x43:
            let bitmapId = try bits.readAlignedUInt16()
            let matrix = try parseMatrix(&bits)
            // 0x40/0x42 repeat (tile); 0x41/0x43 clip. 0x42/0x43 disable
            // smoothing.
            return .bitmap(
                characterId: bitmapId,
                matrix: matrix,
                tiled: type & 0x01 == 0,
                smoothed: type < 0x42
            )
        default:
            throw SWFShapeError.invalidFillStyleType(type)
        }
    }

    /// FILLSTYLEARRAY: UI8 count; 0xFF escapes to a UI16 extended count for
    /// DefineShape2 and later. DefineShape treats 0xFF as a literal count.
    static func parseFillStyleArray(
        _ bits: inout SWFBitReader,
        version: SWFShapeVersion
    ) throws -> [SWFFillStyle] {
        var count = try Int(bits.readAlignedUInt8())
        if count == 0xFF, version.supportsExtendedStyleCount {
            count = try Int(bits.readAlignedUInt16())
        }
        var styles: [SWFFillStyle] = []
        styles.reserveCapacity(min(count, 256))
        for _ in 0 ..< count {
            try styles.append(parseFillStyle(&bits, version: version))
        }
        return styles
    }

    /// LINESTYLEARRAY: UI8 count (0xFF escape as for fills), then LINESTYLE
    /// entries — LINESTYLE2 for DefineShape4.
    static func parseLineStyleArray(
        _ bits: inout SWFBitReader,
        version: SWFShapeVersion
    ) throws -> [SWFLineStyle] {
        var count = try Int(bits.readAlignedUInt8())
        if count == 0xFF, version.supportsExtendedStyleCount {
            count = try Int(bits.readAlignedUInt16())
        }
        var styles: [SWFLineStyle] = []
        styles.reserveCapacity(min(count, 256))
        for _ in 0 ..< count {
            if version.usesLineStyle2 {
                try styles.append(parseLineStyle2(&bits))
            } else {
                let width = try bits.readAlignedUInt16()
                let color = try parseColor(&bits, hasAlpha: version.hasAlphaColors)
                styles.append(SWFLineStyle(width: width, color: color))
            }
        }
        return styles
    }

    /// LINESTYLE2 (DefineShape4): cap/join/scale flag bits, optional miter
    /// limit, then either an RGBA color or a stroke FILLSTYLE.
    static func parseLineStyle2(_ bits: inout SWFBitReader) throws -> SWFLineStyle {
        let width = try bits.readAlignedUInt16()
        let startCap = try capStyle(bits.readUB(2))
        let joinRaw = try bits.readUB(2)
        let hasFill = try bits.readUB(1) == 1
        let noHScale = try bits.readUB(1) == 1
        let noVScale = try bits.readUB(1) == 1
        let pixelHinting = try bits.readUB(1) == 1
        _ = try bits.readUB(5) // Reserved, must be 0
        let noClose = try bits.readUB(1) == 1
        let endCap = try capStyle(bits.readUB(2))
        var join: SWFLineStyle.JoinStyle = joinRaw == 1 ? .bevel : .round
        if joinRaw == 2 {
            // MiterLimitFactor: 8.8 fixed point.
            join = try .miter(limitFactor: Float(bits.readAlignedUInt16()) / 256)
        }
        var color = SWFColor(red: 0, green: 0, blue: 0, alpha: 255)
        var fill: SWFFillStyle?
        if hasFill {
            fill = try parseFillStyle(&bits, version: .shape4)
        } else {
            color = try parseColor(&bits, hasAlpha: true)
        }
        var style = SWFLineStyle(width: width, color: color)
        style.fill = fill
        style.startCap = startCap
        style.endCap = endCap
        style.join = join
        style.noHScale = noHScale
        style.noVScale = noVScale
        style.pixelHinting = pixelHinting
        style.noClose = noClose
        return style
    }

    /// SHAPEWITHSTYLE: style arrays, index bit widths, record stream.
    static func parseShapeWithStyle(
        _ bits: inout SWFBitReader,
        version: SWFShapeVersion
    ) throws -> ShapeContents {
        var walker = ShapeRecordWalker(bits: bits, version: version)
        walker.fillStyles = try parseFillStyleArray(&bits, version: version)
        walker.lineStyles = try parseLineStyleArray(&bits, version: version)
        walker.fillCount = walker.fillStyles.count
        walker.lineCount = walker.lineStyles.count
        walker.bits = bits
        try walker.readIndexBits()
        try walker.walkRecords()
        bits = walker.bits
        return ShapeContents(
            fillStyles: walker.fillStyles,
            lineStyles: walker.lineStyles,
            segments: walker.segments
        )
    }

    /// Bare SHAPE (DefineFont glyphs): index bit widths + records, no style
    /// arrays. Fill indices pass through unresolved (glyph on/off convention).
    static func parseGlyphShape(_ bits: inout SWFBitReader) throws -> [SWFShapeSegment] {
        var walker = ShapeRecordWalker(bits: bits, version: nil)
        try walker.readIndexBits()
        try walker.walkRecords()
        bits = walker.bits
        return walker.segments
    }

    private static func capStyle(_ raw: UInt32) -> SWFLineStyle.CapStyle {
        SWFLineStyle.CapStyle(rawValue: UInt8(raw & 0x03)) ?? .round
    }
}

/// Walks the SHAPERECORD stream, tracking the pen position and the selected
/// styles, and resolves per-record style indices against the flattened global
/// arrays (StateNewStyles appends a new generation and rebases the indices).
/// `version == nil` is glyph mode: no style arrays exist, indices pass
/// through, and StateNewStyles is an error.
private struct ShapeRecordWalker {
    var bits: SWFBitReader
    let version: SWFShapeVersion?
    var fillStyles: [SWFFillStyle] = []
    var lineStyles: [SWFLineStyle] = []
    var segments: [SWFShapeSegment] = []
    var fillCount = 0
    var lineCount = 0
    private var fillIndexBits = 0
    private var lineIndexBits = 0
    private var fillBase = 0
    private var lineBase = 0
    private var fill0 = 0
    private var fill1 = 0
    private var line = 0
    private var penX: Int32 = 0
    private var penY: Int32 = 0

    init(bits: SWFBitReader, version: SWFShapeVersion?) {
        self.bits = bits
        self.version = version
    }

    /// NumFillBits UB[4] + NumLineBits UB[4], byte-aligned after the style
    /// arrays (see alignment note at the top of this file).
    mutating func readIndexBits() throws {
        bits.align()
        fillIndexBits = try Int(bits.readUB(4))
        lineIndexBits = try Int(bits.readUB(4))
    }

    /// Reads records until the EndShapeRecord (six zero bits).
    mutating func walkRecords() throws {
        while true {
            if try bits.readUB(1) == 1 {
                try readEdgeRecord()
            } else {
                let flags = try bits.readUB(5)
                if flags == 0 {
                    return
                }
                try readStyleChangeRecord(flags: flags)
            }
        }
    }

    /// StyleChangeRecord field order: MoveTo, FillStyle0, FillStyle1,
    /// LineStyle, then the NewStyles arrays (spec pp. 127-128). Flag bits from
    /// high to low: StateNewStyles, StateLineStyle, StateFillStyle1,
    /// StateFillStyle0, StateMoveTo.
    private mutating func readStyleChangeRecord(flags: UInt32) throws {
        if flags & 0x01 != 0 {
            let moveBits = try Int(bits.readUB(5))
            // MoveDeltaX/Y are relative to the shape origin, i.e. absolute.
            penX = try bits.readSB(moveBits)
            penY = try bits.readSB(moveBits)
        }
        if flags & 0x02 != 0 {
            fill0 = try resolveIndex(bits.readUB(fillIndexBits), base: fillBase, count: fillCount)
        }
        if flags & 0x04 != 0 {
            fill1 = try resolveIndex(bits.readUB(fillIndexBits), base: fillBase, count: fillCount)
        }
        if flags & 0x08 != 0 {
            line = try resolveIndex(bits.readUB(lineIndexBits), base: lineBase, count: lineCount)
        }
        if flags & 0x10 != 0 {
            try readNewStyles()
        }
    }

    /// Maps a record's 1-based local style index into the flattened global
    /// arrays; 0 stays "no style". Glyph mode passes indices through.
    private func resolveIndex(_ raw: UInt32, base: Int, count: Int) throws -> Int {
        let local = Int(raw)
        guard local > 0 else { return 0 }
        guard version != nil else { return local }
        guard local <= count else {
            throw SWFShapeError.styleIndexOutOfRange(index: local, count: count)
        }
        return base + local
    }

    /// StateNewStyles: fresh style arrays plus new index bit widths. Used by
    /// DefineShape2 and later per the spec; a glyph SHAPE has nowhere to put
    /// styles, so it is rejected there.
    private mutating func readNewStyles() throws {
        guard let version else { throw SWFShapeError.newStylesInGlyph }
        let newFills = try SWFShapeParser.parseFillStyleArray(&bits, version: version)
        let newLines = try SWFShapeParser.parseLineStyleArray(&bits, version: version)
        fillBase = fillStyles.count
        lineBase = lineStyles.count
        fillCount = newFills.count
        lineCount = newLines.count
        fillStyles += newFills
        lineStyles += newLines
        try readIndexBits()
    }

    /// StraightEdgeRecord / CurvedEdgeRecord (spec pp. 129-131). Deltas use
    /// wrapping adds so malformed extremes cannot trap.
    private mutating func readEdgeRecord() throws {
        let straight = try bits.readUB(1) == 1
        let numBits = try Int(bits.readUB(4)) + 2
        let edge: SWFShapeSegment.Edge
        let fromX = penX
        let fromY = penY
        if straight {
            var deltaX: Int32 = 0
            var deltaY: Int32 = 0
            let generalLine = try bits.readUB(1) == 1
            if generalLine {
                deltaX = try bits.readSB(numBits)
                deltaY = try bits.readSB(numBits)
            } else if try bits.readUB(1) == 1 { // VertLineFlag
                deltaY = try bits.readSB(numBits)
            } else {
                deltaX = try bits.readSB(numBits)
            }
            penX = penX &+ deltaX
            penY = penY &+ deltaY
            edge = .line(toX: penX, toY: penY)
        } else {
            let controlX = try penX &+ bits.readSB(numBits)
            let controlY = try penY &+ bits.readSB(numBits)
            penX = try controlX &+ bits.readSB(numBits)
            penY = try controlY &+ bits.readSB(numBits)
            edge = .quadratic(controlX: controlX, controlY: controlY, toX: penX, toY: penY)
        }
        segments.append(SWFShapeSegment(
            fromX: fromX,
            fromY: fromY,
            edge: edge,
            fillStyle0: fill0,
            fillStyle1: fill1,
            lineStyle: line
        ))
    }
}
