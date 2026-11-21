// Synthetic DefineMorphShape and DefineMorphShape2 tag bodies, built bit by bit
// from the Adobe SWF File Format Specification v19 layouts.

import Foundation
@testable public import OpenSkyFormatsSWF

/// A morph from a 100-twip square to a 300-twip square. The last edge is a line
/// in the start form and a curve in the end form.
public enum SWFMorphShapeFixture {
    public static let startColor = SWFColor(red: 0, green: 0, blue: 0, alpha: 255)
    public static let endColor = SWFColor(red: 200, green: 100, blue: 50, alpha: 55)
    public static let startWidth: UInt16 = 20
    public static let endWidth: UInt16 = 60
    /// Start cap none, bevel join, no close, end cap square.
    public static let lineFlags: UInt32 = 1 << 14 | 1 << 12 | 0x0004 | 2

    public static func tag(
        characterId: UInt16,
        version2: Bool = false,
        dropEndEdge: Bool = false,
        scale: Int32 = 1
    ) -> SWFFixture.Tag {
        var head = SWFShapeBodyBuilder()
        head.appendCharacterId(characterId)
        head.appendRect(xMin: 0, xMax: 100 * scale, yMin: 0, yMax: 100 * scale)
        head.appendRect(xMin: 0, xMax: 300 * scale, yMin: 0, yMax: 300 * scale)
        if version2 {
            head.appendRect(xMin: 0, xMax: 100 * scale, yMin: 0, yMax: 100 * scale)
            head.appendRect(xMin: 0, xMax: 300 * scale, yMin: 0, yMax: 300 * scale)
            head.writer.align()
            head.writer.appendByte(0)
        }
        let styles = stylesAndStartEdges(version2: version2, scale: scale)
        head.writer.align()
        head.writer.appendUInt32LE(UInt32(styles.count))
        var body = head.build()
        body.append(styles)
        body.append(endEdges(dropLast: dropEndEdge, scale: scale))
        return SWFFixture.Tag(code: version2 ? 84 : 46, body: body)
    }

    private static func stylesAndStartEdges(version2: Bool, scale: Int32) -> Data {
        var builder = SWFShapeBodyBuilder()
        builder.appendStyleCount(1)
        builder.writer.appendByte(0x00)
        builder.appendColor(startColor, rgba: true)
        builder.appendColor(endColor, rgba: true)
        builder.appendStyleCount(1)
        builder.writer.appendUInt16LE(startWidth)
        builder.writer.appendUInt16LE(endWidth)
        if version2 {
            builder.writer.writeUB(lineFlags, count: 16)
        }
        builder.appendColor(startColor, rgba: true)
        builder.appendColor(endColor, rgba: true)
        builder.appendIndexBits(fill: 1, line: 1)
        builder.appendStyleChange(.init(moveToX: 0, moveToY: 0, fill1: 1, line: 1))
        builder.appendAxisEdge(delta: 100 * scale, vertical: false)
        builder.appendAxisEdge(delta: 100 * scale, vertical: true)
        builder.appendAxisEdge(delta: -100 * scale, vertical: false)
        builder.appendAxisEdge(delta: -100 * scale, vertical: true)
        builder.appendEndRecord()
        builder.writer.align()
        return builder.build()
    }

    private static func endEdges(dropLast: Bool, scale: Int32) -> Data {
        var builder = SWFShapeBodyBuilder()
        builder.appendIndexBits(fill: 0, line: 0)
        builder.appendStyleChange(.init(moveToX: 0, moveToY: 0))
        builder.appendAxisEdge(delta: 300 * scale, vertical: false)
        builder.appendAxisEdge(delta: 300 * scale, vertical: true)
        builder.appendAxisEdge(delta: -300 * scale, vertical: false)
        if !dropLast {
            builder.appendCurvedEdge(
                controlDeltaX: -50 * scale, controlDeltaY: -150 * scale,
                anchorDeltaX: 50 * scale, anchorDeltaY: -150 * scale
            )
        }
        builder.appendEndRecord()
        return builder.build()
    }
}
