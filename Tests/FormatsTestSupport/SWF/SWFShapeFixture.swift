// Synthetic DefineShape tag-body builder for shape parser tests. Bodies are
// assembled bit-by-bit in code following the Adobe SWF File Format
// Specification v19 chapter 6 layouts — never extracted game files
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import OpenSkyFormats

/// Assembles a DefineShape/2/3/4 tag body through `SWFBitWriter`, mirroring
/// the bit packing `SWFShapeParser` reads back.
public struct SWFShapeBodyBuilder: Sendable {
    public var writer = SWFBitWriter()
    private var fillIndexBits = 0
    private var lineIndexBits = 0

    public func build() -> Data {
        writer.bytes()
    }

    public mutating func appendCharacterId(_ characterId: UInt16) {
        writer.appendUInt16LE(characterId)
    }

    public mutating func appendRect(xMin: Int32, xMax: Int32, yMin: Int32, yMax: Int32) {
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
    public mutating func appendShape4Flags(usesWindingRule: Bool) {
        writer.align()
        writer.writeUB(0, count: 5)
        writer.writeUB(usesWindingRule ? 1 : 0, count: 1)
        writer.writeUB(0, count: 2)
    }

    /// FILLSTYLEARRAY / LINESTYLEARRAY count byte, with the 0xFF UI16 escape.
    public mutating func appendStyleCount(_ count: Int, extended: Bool = false) {
        if extended {
            writer.appendByte(0xFF)
            writer.appendUInt16LE(UInt16(count))
        } else {
            writer.appendByte(UInt8(count))
        }
    }

    public mutating func appendColor(_ color: SWFColor, rgba: Bool) {
        writer.appendBytes([color.red, color.green, color.blue])
        if rgba {
            writer.appendByte(color.alpha)
        }
    }

    public mutating func appendSolidFill(_ color: SWFColor, rgba: Bool) {
        writer.appendByte(0x00)
        appendColor(color, rgba: rgba)
    }

    /// Translation-only MATRIX (HasScale = HasRotate = 0).
    public mutating func appendMatrix(translateX: Int32, translateY: Int32) {
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
    public mutating func appendGradientFill(
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

    public mutating func appendBitmapFill(type: UInt8, characterId: UInt16) {
        writer.appendByte(type)
        writer.appendUInt16LE(characterId)
        appendMatrix(translateX: 0, translateY: 0)
    }

    public mutating func appendLineStyle(width: UInt16, color: SWFColor, rgba: Bool) {
        writer.appendUInt16LE(width)
        appendColor(color, rgba: rgba)
    }

    /// NumFillBits UB[4] + NumLineBits UB[4]; the widths are reused by the
    /// style-change records that follow.
    public mutating func appendIndexBits(fill: Int, line: Int) {
        writer.align()
        writer.writeUB(UInt32(fill), count: 4)
        writer.writeUB(UInt32(line), count: 4)
        fillIndexBits = fill
        lineIndexBits = line
    }

    /// StyleChangeRecord contents; `newStyles` writes only the flag — the
    /// caller appends the new style arrays and index bits right after.
    public struct StyleChange: Sendable {
        public var moveToX: Int32?
        public var moveToY: Int32?
        public var fill0: Int?
        public var fill1: Int?
        public var line: Int?
        public var newStyles = false

        public init(
            moveToX: Int32? = nil,
            moveToY: Int32? = nil,
            fill0: Int? = nil,
            fill1: Int? = nil,
            line: Int? = nil,
            newStyles: Bool = false
        ) {
            self.moveToX = moveToX
            self.moveToY = moveToY
            self.fill0 = fill0
            self.fill1 = fill1
            self.line = line
            self.newStyles = newStyles
        }
    }

    public mutating func appendStyleChange(_ change: StyleChange) {
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

    public mutating func appendMoveTo(x: Int32, y: Int32) {
        appendStyleChange(StyleChange(moveToX: x, moveToY: y))
    }

    /// General straight edge carrying both deltas.
    public mutating func appendStraightEdge(deltaX: Int32, deltaY: Int32) {
        writer.writeUB(1, count: 1) // edge record
        writer.writeUB(1, count: 1) // straight
        let nbits = edgeBits(deltaX, deltaY)
        writer.writeUB(UInt32(nbits - 2), count: 4)
        writer.writeUB(1, count: 1) // GeneralLineFlag
        writer.writeSB(deltaX, count: nbits)
        writer.writeSB(deltaY, count: nbits)
    }

    /// Vert/horz straight edge (GeneralLineFlag = 0) carrying one delta.
    public mutating func appendAxisEdge(delta: Int32, vertical: Bool) {
        writer.writeUB(1, count: 1)
        writer.writeUB(1, count: 1)
        let nbits = edgeBits(delta, 0)
        writer.writeUB(UInt32(nbits - 2), count: 4)
        writer.writeUB(0, count: 1) // GeneralLineFlag
        writer.writeUB(vertical ? 1 : 0, count: 1) // VertLineFlag
        writer.writeSB(delta, count: nbits)
    }

    public mutating func appendCurvedEdge(
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
    public mutating func appendEndRecord() {
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

    public init(writer: SWFBitWriter = SWFBitWriter()) {
        self.writer = writer
    }
}
