// Unit tests for DefineShape tag decoding: fill/line style arrays, MATRIX
// and GRADIENT records, shape records, per-version RGB/RGBA rules, extended
// style counts, and defensive failure on malformed bodies. All fixtures are
// synthetic, built through SWFShapeBodyBuilder.

import Foundation
@testable import opensky
import Testing

struct SWFShapeTests {
    private let red = SWFColor(red: 255, green: 0, blue: 0, alpha: 255)
    private let translucentBlue = SWFColor(red: 0, green: 0, blue: 255, alpha: 128)

    /// A DefineShape (RGB) unit square: one solid fill, move-to, four
    /// straight edges exercising general, horizontal, and vertical forms.
    private func solidSquareBody(fill1: Int = 1) -> Data {
        var builder = SWFShapeBodyBuilder()
        builder.appendCharacterId(7)
        builder.appendRect(xMin: 0, xMax: 200, yMin: 0, yMax: 200)
        builder.appendStyleCount(1)
        builder.appendSolidFill(red, rgba: false)
        builder.appendStyleCount(0)
        // Two fill index bits so the out-of-range test can encode index 3.
        builder.appendIndexBits(fill: 2, line: 0)
        var change = SWFShapeBodyBuilder.StyleChange(moveToX: 0, moveToY: 0)
        change.fill1 = fill1
        builder.appendStyleChange(change)
        builder.appendAxisEdge(delta: 200, vertical: false)
        builder.appendAxisEdge(delta: 200, vertical: true)
        builder.appendStraightEdge(deltaX: -200, deltaY: 0)
        builder.appendStraightEdge(deltaX: 0, deltaY: -200)
        builder.appendEndRecord()
        return builder.build()
    }

    @Test func parsesDefineShapeSolidSquare() throws {
        let tag = SWFTag(code: 2, body: solidSquareBody())
        let shape = try SWFShapeDefinition.parse(tag: tag)
        #expect(shape.characterId == 7)
        #expect(shape.bounds == SWFRect(xMin: 0, xMax: 200, yMin: 0, yMax: 200))
        #expect(shape.edgeBounds == nil)
        #expect(shape.fillStyles == [.solid(red)])
        #expect(shape.lineStyles.isEmpty)
        #expect(shape.segments.count == 4)
        // RGB colors parse opaque; every edge carries fill1 = 1, no fill0.
        for segment in shape.segments {
            #expect(segment.fillStyle0 == 0)
            #expect(segment.fillStyle1 == 1)
            #expect(segment.lineStyle == 0)
        }
        // Horizontal, vertical, then two general edges walk the square back
        // to the origin.
        #expect(shape.segments[0].edge == .line(toX: 200, toY: 0))
        #expect(shape.segments[1].edge == .line(toX: 200, toY: 200))
        #expect(shape.segments[2].edge == .line(toX: 0, toY: 200))
        #expect(shape.segments[3].edge == .line(toX: 0, toY: 0))
        #expect(shape.segments[3].endPoint == (0, 0))
    }

    @Test func parsesDefineShape3AlphaStylesAndLineStyle() throws {
        var builder = SWFShapeBodyBuilder()
        builder.appendCharacterId(9)
        builder.appendRect(xMin: -100, xMax: 100, yMin: -100, yMax: 100)
        builder.appendStyleCount(2)
        builder.appendSolidFill(translucentBlue, rgba: true)
        builder.appendGradientFill(
            type: 0x10,
            translate: 40,
            stops: [
                SWFGradientRecord(ratio: 0, color: red),
                SWFGradientRecord(ratio: 255, color: translucentBlue)
            ],
            rgba: true
        )
        builder.appendStyleCount(1)
        builder.appendLineStyle(width: 20, color: translucentBlue, rgba: true)
        builder.appendIndexBits(fill: 2, line: 1)
        var change = SWFShapeBodyBuilder.StyleChange(moveToX: -100, moveToY: -100)
        change.fill1 = 2
        change.line = 1
        builder.appendStyleChange(change)
        builder.appendCurvedEdge(
            controlDeltaX: 100,
            controlDeltaY: 0,
            anchorDeltaX: 100,
            anchorDeltaY: 100
        )
        builder.appendEndRecord()

        let shape = try SWFShapeDefinition.parse(tag: SWFTag(code: 32, body: builder.build()))
        #expect(shape.fillStyles[0] == .solid(translucentBlue))
        guard case let .linearGradient(matrix, gradient) = shape.fillStyles[1] else {
            Issue.record("expected linearGradient, got \(shape.fillStyles[1])")
            return
        }
        #expect(matrix.translateX == 40)
        #expect(matrix.translateY == 40)
        #expect(gradient.spreadMode == .pad)
        #expect(gradient.interpolationMode == .normalRGB)
        #expect(gradient.focalPoint == nil)
        #expect(gradient.records.count == 2)
        #expect(gradient.records[1].color.alpha == 128)
        #expect(shape.lineStyles == [SWFLineStyle(width: 20, color: translucentBlue)])
        #expect(shape.segments.count == 1)
        #expect(shape.segments[0].fillStyle1 == 2)
        #expect(shape.segments[0].lineStyle == 1)
        #expect(shape.segments[0].edge == .quadratic(controlX: 0, controlY: -100, toX: 100, toY: 0))
    }

    @Test func parsesBitmapFillVariants() throws {
        var builder = SWFShapeBodyBuilder()
        builder.appendCharacterId(3)
        builder.appendRect(xMin: 0, xMax: 10, yMin: 0, yMax: 10)
        builder.appendStyleCount(2)
        builder.appendBitmapFill(type: 0x41, characterId: 55) // clipped, smoothed
        builder.appendBitmapFill(type: 0x42, characterId: 56) // repeating, non-smoothed
        builder.appendStyleCount(0)
        builder.appendIndexBits(fill: 2, line: 0)
        builder.appendEndRecord()

        let shape = try SWFShapeDefinition.parse(tag: SWFTag(code: 22, body: builder.build()))
        #expect(shape.fillStyles[0] == .bitmap(
            characterId: 55,
            matrix: .identity,
            tiled: false,
            smoothed: true
        ))
        #expect(shape.fillStyles[1] == .bitmap(
            characterId: 56,
            matrix: .identity,
            tiled: true,
            smoothed: false
        ))
    }

    @Test func parsesExtendedStyleCountInDefineShape2() throws {
        var builder = SWFShapeBodyBuilder()
        builder.appendCharacterId(1)
        builder.appendRect(xMin: 0, xMax: 10, yMin: 0, yMax: 10)
        builder.appendStyleCount(2, extended: true) // 0xFF marker + UI16 count
        builder.appendSolidFill(red, rgba: false)
        builder.appendSolidFill(red, rgba: false)
        builder.appendStyleCount(0)
        builder.appendIndexBits(fill: 2, line: 0)
        builder.appendEndRecord()

        let shape = try SWFShapeDefinition.parse(tag: SWFTag(code: 22, body: builder.build()))
        #expect(shape.fillStyles.count == 2)
    }

    @Test func parsesDefineShape4EdgeBoundsFlagsAndLineStyle2() throws {
        var builder = SWFShapeBodyBuilder()
        builder.appendCharacterId(12)
        builder.appendRect(xMin: 0, xMax: 400, yMin: 0, yMax: 400)
        builder.appendRect(xMin: 10, xMax: 390, yMin: 10, yMax: 390)
        builder.appendShape4Flags(usesWindingRule: true)
        builder.appendStyleCount(1)
        builder.appendSolidFill(translucentBlue, rgba: true)
        builder.appendStyleCount(1)
        // LINESTYLE2: square start cap, miter join (limit 4.0), no fill,
        // pixel hinting, no-close, round end cap.
        builder.writer.appendUInt16LE(40) // width
        builder.writer.writeUB(2, count: 2) // StartCapStyle square
        builder.writer.writeUB(2, count: 2) // JoinStyle miter
        builder.writer.writeUB(0, count: 1) // HasFillFlag
        builder.writer.writeUB(1, count: 1) // NoHScaleFlag
        builder.writer.writeUB(0, count: 1) // NoVScaleFlag
        builder.writer.writeUB(1, count: 1) // PixelHintingFlag
        builder.writer.writeUB(0, count: 5) // Reserved
        builder.writer.writeUB(1, count: 1) // NoClose
        builder.writer.writeUB(0, count: 2) // EndCapStyle round
        builder.writer.appendUInt16LE(4 << 8) // MiterLimitFactor 4.0 in 8.8
        builder.appendColor(red, rgba: true)
        builder.appendIndexBits(fill: 1, line: 1)
        builder.appendEndRecord()

        let shape = try SWFShapeDefinition.parse(tag: SWFTag(code: 83, body: builder.build()))
        #expect(shape.edgeBounds == SWFRect(xMin: 10, xMax: 390, yMin: 10, yMax: 390))
        #expect(shape.usesFillWindingRule)
        #expect(shape.lineStyles.count == 1)
        let line = try #require(shape.lineStyles.first)
        #expect(line.width == 40)
        #expect(line.startCap == .square)
        #expect(line.endCap == .round)
        #expect(line.join == .miter(limitFactor: 4))
        #expect(line.fill == nil)
        #expect(line.color == red)
        #expect(line.noHScale)
        #expect(!line.noVScale)
        #expect(line.pixelHinting)
        #expect(line.noClose)
    }

    @Test func flattensNewStyleArraysIntoGlobalIndices() throws {
        var builder = SWFShapeBodyBuilder()
        builder.appendCharacterId(4)
        builder.appendRect(xMin: 0, xMax: 100, yMin: 0, yMax: 100)
        builder.appendStyleCount(1)
        builder.appendSolidFill(red, rgba: false)
        builder.appendStyleCount(0)
        builder.appendIndexBits(fill: 1, line: 0)
        var first = SWFShapeBodyBuilder.StyleChange(moveToX: 0, moveToY: 0)
        first.fill1 = 1
        builder.appendStyleChange(first)
        builder.appendAxisEdge(delta: 100, vertical: false)
        // Replace the style arrays mid-shape; the following edge references
        // index 1 of the new generation.
        builder.appendStyleChange(SWFShapeBodyBuilder.StyleChange(newStyles: true))
        builder.appendStyleCount(2)
        builder.appendSolidFill(translucentBlue, rgba: false)
        builder.appendSolidFill(red, rgba: false)
        builder.appendStyleCount(0)
        builder.appendIndexBits(fill: 2, line: 0)
        var second = SWFShapeBodyBuilder.StyleChange()
        second.fill1 = 1
        builder.appendStyleChange(second)
        builder.appendAxisEdge(delta: 100, vertical: true)
        builder.appendEndRecord()

        let shape = try SWFShapeDefinition.parse(tag: SWFTag(code: 22, body: builder.build()))
        #expect(shape.fillStyles.count == 3)
        #expect(shape.segments.count == 2)
        #expect(shape.segments[0].fillStyle1 == 1) // first generation, index 1
        #expect(shape.segments[1].fillStyle1 == 2) // second generation rebased
    }

    @Test func parsesGlyphShapeWithPassthroughIndices() throws {
        var builder = SWFShapeBodyBuilder()
        builder.appendIndexBits(fill: 1, line: 0)
        var change = SWFShapeBodyBuilder.StyleChange(moveToX: 5, moveToY: 5)
        change.fill1 = 1
        builder.appendStyleChange(change)
        builder.appendStraightEdge(deltaX: 10, deltaY: 0)
        builder.appendStraightEdge(deltaX: -10, deltaY: 10)
        builder.appendStraightEdge(deltaX: 0, deltaY: -10)
        builder.appendEndRecord()

        var bits = SWFBitReader(builder.build())
        let segments = try SWFShapeDefinition.parseGlyphSegments(&bits)
        #expect(segments.count == 3)
        #expect(segments[0].fillStyle1 == 1)
        #expect(segments[0].fromX == 5)
        #expect(segments[2].endPoint == (5, 5))
    }

    @Test func rejectsUnsupportedTagAndBadFillType() {
        #expect(throws: SWFShapeError.unsupportedTag(1)) {
            _ = try SWFShapeDefinition.parse(tag: SWFTag(code: 1, body: Data()))
        }
        var builder = SWFShapeBodyBuilder()
        builder.appendCharacterId(2)
        builder.appendRect(xMin: 0, xMax: 10, yMin: 0, yMax: 10)
        builder.appendStyleCount(1)
        builder.writer.appendByte(0x99) // invalid FillStyleType
        let body = builder.build()
        #expect(throws: SWFShapeError.invalidFillStyleType(0x99)) {
            _ = try SWFShapeDefinition.parse(tag: SWFTag(code: 2, body: body))
        }
    }

    @Test func rejectsTruncatedBodyWithTypedError() {
        let body = solidSquareBody()
        let truncated = body.prefix(body.count - 2)
        #expect(throws: (any Error).self) {
            _ = try SWFShapeDefinition.parse(tag: SWFTag(code: 2, body: Data(truncated)))
        }
    }

    @Test func rejectsOutOfRangeStyleIndex() {
        // fill1 = 3 with only one declared fill style.
        let body = solidSquareBody(fill1: 3)
        #expect(throws: SWFShapeError.styleIndexOutOfRange(index: 3, count: 1)) {
            _ = try SWFShapeDefinition.parse(tag: SWFTag(code: 2, body: body))
        }
    }
}
