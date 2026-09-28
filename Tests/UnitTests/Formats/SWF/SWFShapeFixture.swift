// Synthetic DefineShape tag-body builder for shape parser tests. Bodies are
// assembled bit-by-bit in code following the Adobe SWF File Format
// Specification v19 chapter 6 layouts — never extracted game files
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky

/// Assembles a DefineShape/2/3/4 tag body through `SWFBitWriter`, mirroring
/// the bit packing `SWFShapeParser` reads back.
struct SWFShapeBodyBuilder {
    var writer = SWFBitWriter()
    private var fillIndexBits = 0
    private var lineIndexBits = 0

    func build() -> Data {
        writer.bytes()
    }

    mutating func appendCharacterId(_ characterId: UInt16) {
        writer.appendUInt16LE(characterId)
    }

    mutating func appendRect(xMin: Int32, xMax: Int32, yMin: Int32, yMax: Int32) {
        writer.align()
        let fields = [xMin, xMax, yMin, yMax]
        let nbits = fields.map(SWFFixture.signedBitWidth).max() ?? 1
        writer.writeUB(UInt32(nbits), count: 5)
        for field in fields {
            writer.writeSB(field, count: nbits)
        }
    }

    /// DefineShape4 flag byte: Reserved UB[5], UsesFillWindingRule,
    /// UsesNonScalingStrokes, UsesScalingStrokes.
    mutating func appendShape4Flags(usesWindingRule: Bool) {
        writer.align()
        writer.writeUB(0, count: 5)
        writer.writeUB(usesWindingRule ? 1 : 0, count: 1)
        writer.writeUB(0, count: 2)
    }

    /// FILLSTYLEARRAY / LINESTYLEARRAY count byte, with the 0xFF UI16 escape.
    mutating func appendStyleCount(_ count: Int, extended: Bool = false) {
        if extended {
            writer.appendByte(0xFF)
            writer.appendUInt16LE(UInt16(count))
        } else {
            writer.appendByte(UInt8(count))
        }
    }

    mutating func appendColor(_ color: SWFColor, rgba: Bool) {
        writer.appendBytes([color.red, color.green, color.blue])
        if rgba {
            writer.appendByte(color.alpha)
        }
    }

    mutating func appendSolidFill(_ color: SWFColor, rgba: Bool) {
        writer.appendByte(0x00)
        appendColor(color, rgba: rgba)
    }

    /// Translation-only MATRIX (HasScale = HasRotate = 0).
    mutating func appendMatrix(translateX: Int32, translateY: Int32) {
        writer.align()
        writer.writeUB(0, count: 1)
        writer.writeUB(0, count: 1)
        let nbits = max(
            SWFFixture.signedBitWidth(translateX),
            SWFFixture.signedBitWidth(translateY)
        )
        writer.writeUB(UInt32(nbits), count: 5)
        writer.writeSB(translateX, count: nbits)
        writer.writeSB(translateY, count: nbits)
    }

    /// Linear (0x10) or radial (0x12) gradient fill with a translation-only
    /// matrix and pad spread / normal interpolation.
    mutating func appendGradientFill(
        type: UInt8,
        translate: Int32,
        stops: [SWFGradientRecord],
        rgba: Bool
    ) {
        writer.appendByte(type)
        appendMatrix(translateX: translate, translateY: translate)
        writer.align()
        writer.writeUB(0, count: 2) // SpreadMode pad
        writer.writeUB(0, count: 2) // InterpolationMode normal RGB
        writer.writeUB(UInt32(stops.count), count: 4)
        for stop in stops {
            writer.appendByte(stop.ratio)
            appendColor(stop.color, rgba: rgba)
        }
    }

    mutating func appendBitmapFill(type: UInt8, characterId: UInt16) {
        writer.appendByte(type)
        writer.appendUInt16LE(characterId)
        appendMatrix(translateX: 0, translateY: 0)
    }

    mutating func appendLineStyle(width: UInt16, color: SWFColor, rgba: Bool) {
        writer.appendUInt16LE(width)
        appendColor(color, rgba: rgba)
    }

    /// NumFillBits UB[4] + NumLineBits UB[4]; the widths are reused by the
    /// style-change records that follow.
    mutating func appendIndexBits(fill: Int, line: Int) {
        writer.align()
        writer.writeUB(UInt32(fill), count: 4)
        writer.writeUB(UInt32(line), count: 4)
        fillIndexBits = fill
        lineIndexBits = line
    }

    /// StyleChangeRecord contents; `newStyles` writes only the flag — the
    /// caller appends the new style arrays and index bits right after.
    struct StyleChange {
        var moveToX: Int32?
        var moveToY: Int32?
        var fill0: Int?
        var fill1: Int?
        var line: Int?
        var newStyles = false
    }

    mutating func appendStyleChange(_ change: StyleChange) {
        writer.writeUB(0, count: 1) // non-edge record
        writer.writeUB(change.newStyles ? 1 : 0, count: 1)
        writer.writeUB(change.line != nil ? 1 : 0, count: 1)
        writer.writeUB(change.fill1 != nil ? 1 : 0, count: 1)
        writer.writeUB(change.fill0 != nil ? 1 : 0, count: 1)
        writer.writeUB(change.moveToX != nil ? 1 : 0, count: 1)
        if let moveX = change.moveToX, let moveY = change.moveToY {
            let moveBits = max(
                SWFFixture.signedBitWidth(moveX),
                SWFFixture.signedBitWidth(moveY)
            )
            writer.writeUB(UInt32(moveBits), count: 5)
            writer.writeSB(moveX, count: moveBits)
            writer.writeSB(moveY, count: moveBits)
        }
        if let fill0 = change.fill0 {
            writer.writeUB(UInt32(fill0), count: fillIndexBits)
        }
        if let fill1 = change.fill1 {
            writer.writeUB(UInt32(fill1), count: fillIndexBits)
        }
        if let line = change.line {
            writer.writeUB(UInt32(line), count: lineIndexBits)
        }
    }

    mutating func appendMoveTo(x: Int32, y: Int32) {
        appendStyleChange(StyleChange(moveToX: x, moveToY: y))
    }

    /// General straight edge carrying both deltas.
    mutating func appendStraightEdge(deltaX: Int32, deltaY: Int32) {
        writer.writeUB(1, count: 1) // edge record
        writer.writeUB(1, count: 1) // straight
        let nbits = edgeBits(deltaX, deltaY)
        writer.writeUB(UInt32(nbits - 2), count: 4)
        writer.writeUB(1, count: 1) // GeneralLineFlag
        writer.writeSB(deltaX, count: nbits)
        writer.writeSB(deltaY, count: nbits)
    }

    /// Vert/horz straight edge (GeneralLineFlag = 0) carrying one delta.
    mutating func appendAxisEdge(delta: Int32, vertical: Bool) {
        writer.writeUB(1, count: 1)
        writer.writeUB(1, count: 1)
        let nbits = edgeBits(delta, 0)
        writer.writeUB(UInt32(nbits - 2), count: 4)
        writer.writeUB(0, count: 1) // GeneralLineFlag
        writer.writeUB(vertical ? 1 : 0, count: 1) // VertLineFlag
        writer.writeSB(delta, count: nbits)
    }

    mutating func appendCurvedEdge(
        controlDeltaX: Int32,
        controlDeltaY: Int32,
        anchorDeltaX: Int32,
        anchorDeltaY: Int32
    ) {
        writer.writeUB(1, count: 1) // edge record
        writer.writeUB(0, count: 1) // curved
        let nbits = max(
            edgeBits(controlDeltaX, controlDeltaY),
            edgeBits(anchorDeltaX, anchorDeltaY)
        )
        writer.writeUB(UInt32(nbits - 2), count: 4)
        writer.writeSB(controlDeltaX, count: nbits)
        writer.writeSB(controlDeltaY, count: nbits)
        writer.writeSB(anchorDeltaX, count: nbits)
        writer.writeSB(anchorDeltaY, count: nbits)
    }

    /// EndShapeRecord: six zero bits.
    mutating func appendEndRecord() {
        writer.writeUB(0, count: 6)
    }

    /// NumBits fields store two less than the actual width; minimum width 2.
    private func edgeBits(_ first: Int32, _ second: Int32) -> Int {
        max(
            2,
            SWFFixture.signedBitWidth(first),
            SWFFixture.signedBitWidth(second)
        )
    }
}
