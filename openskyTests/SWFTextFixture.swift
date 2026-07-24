// Synthetic DefineText/DefineText2/DefineEditText tag-body builders for the
// static-text parser tests. Assembled bit-by-bit in code following the Adobe
// SWF File Format Specification v19 chapter 10 layouts — never extracted game
// files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky

/// Assembles a DefineText (11) / DefineText2 (33) tag body.
struct SWFTextBodyBuilder {
    /// One glyph placement inside a text record.
    struct Glyph {
        let index: Int
        let advance: Int32
    }

    /// One TEXTRECORD: optional state changes then glyph placements.
    struct Record {
        var fontID: UInt16?
        var textHeight: UInt16?
        var color: SWFColor?
        var xOffset: Int16?
        var yOffset: Int16?
        var glyphs: [Glyph] = []
    }

    var characterId: UInt16 = 1
    var bounds = SWFRect(xMin: 0, xMax: 2000, yMin: 0, yMax: 400)
    var translateX: Int32 = 0
    var translateY: Int32 = 0
    /// DefineText2 stores RGBA colors; DefineText stores RGB.
    var rgba = false
    var glyphBits = 8
    var advanceBits = 12
    var records: [Record] = []

    var writer = SWFBitWriter()

    mutating func build() -> Data {
        writer = SWFBitWriter()
        writer.appendUInt16LE(characterId)
        appendRect(bounds)
        appendTranslateMatrix()
        writer.appendByte(UInt8(glyphBits))
        writer.appendByte(UInt8(advanceBits))
        for record in records {
            appendRecord(record)
        }
        writer.appendByte(0) // end-of-records
        return writer.bytes()
    }

    private mutating func appendRecord(_ record: Record) {
        var flags: UInt8 = 0x80 // TextRecordType
        if record.fontID != nil {
            flags |= 0x08
        }
        if record.color != nil {
            flags |= 0x04
        }
        if record.yOffset != nil {
            flags |= 0x02
        }
        if record.xOffset != nil {
            flags |= 0x01
        }
        writer.appendByte(flags)
        if let fontID = record.fontID {
            writer.appendUInt16LE(fontID)
        }
        if let color = record.color {
            appendColor(color)
        }
        if let xOffset = record.xOffset {
            writer.appendUInt16LE(UInt16(bitPattern: xOffset))
        }
        if let yOffset = record.yOffset {
            writer.appendUInt16LE(UInt16(bitPattern: yOffset))
        }
        if let textHeight = record.textHeight {
            writer.appendUInt16LE(textHeight)
        }
        writer.appendByte(UInt8(record.glyphs.count))
        for glyph in record.glyphs {
            writer.writeUB(UInt32(glyph.index), count: glyphBits)
            writer.writeSB(glyph.advance, count: advanceBits)
        }
    }

    private mutating func appendColor(_ color: SWFColor) {
        writer.appendBytes([color.red, color.green, color.blue])
        if rgba {
            writer.appendByte(color.alpha)
        }
    }

    private mutating func appendRect(_ rect: SWFRect) {
        writer.align()
        let fields = [rect.xMin, rect.xMax, rect.yMin, rect.yMax]
        let nbits = fields.map(SWFFixture.signedBitWidth).max() ?? 1
        writer.writeUB(UInt32(nbits), count: 5)
        for field in fields {
            writer.writeSB(field, count: nbits)
        }
    }

    /// Translation-only MATRIX (HasScale = HasRotate = 0).
    private mutating func appendTranslateMatrix() {
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
}

/// Assembles a DefineEditText (37) tag body.
struct SWFEditTextBodyBuilder {
    var characterId: UInt16 = 1
    var bounds = SWFRect(xMin: 0, xMax: 4000, yMin: 0, yMax: 800)
    var flags = SWFEditTextFlags()
    var fontID: UInt16?
    var fontClass: String?
    var fontHeight: UInt16?
    var color: SWFColor?
    var maxLength: UInt16?
    var layout: SWFEditTextLayout?
    var variableName = ""
    var initialText: String?

    var writer = SWFBitWriter()

    mutating func build() -> Data {
        writer = SWFBitWriter()
        writer.appendUInt16LE(characterId)
        appendRect(bounds)
        appendFlags()
        if let fontID {
            writer.appendUInt16LE(fontID)
        }
        if let fontClass {
            appendString(fontClass)
        }
        if let fontHeight {
            writer.appendUInt16LE(fontHeight)
        }
        if let color {
            writer.appendBytes([color.red, color.green, color.blue, color.alpha])
        }
        if let maxLength {
            writer.appendUInt16LE(maxLength)
        }
        if let layout {
            appendLayout(layout)
        }
        appendString(variableName)
        if let initialText {
            appendString(initialText)
        }
        return writer.bytes()
    }

    private mutating func appendFlags() {
        writer.align()
        let order = [
            flags.hasText, flags.wordWrap, flags.multiline, flags.password,
            flags.readOnly, flags.hasTextColor, flags.hasMaxLength, flags.hasFont,
            flags.hasFontClass, flags.autoSize, flags.hasLayout, flags.noSelect,
            flags.border, flags.wasStatic, flags.html, flags.useOutlines
        ]
        for flag in order {
            writer.writeUB(flag ? 1 : 0, count: 1)
        }
    }

    private mutating func appendLayout(_ layout: SWFEditTextLayout) {
        writer.appendByte(layout.align)
        writer.appendUInt16LE(layout.leftMargin)
        writer.appendUInt16LE(layout.rightMargin)
        writer.appendUInt16LE(layout.indent)
        writer.appendUInt16LE(UInt16(bitPattern: layout.leading))
    }

    private mutating func appendString(_ string: String) {
        writer.appendBytes(Array(string.utf8))
        writer.appendByte(0)
    }

    private mutating func appendRect(_ rect: SWFRect) {
        writer.align()
        let fields = [rect.xMin, rect.xMax, rect.yMin, rect.yMax]
        let nbits = fields.map(SWFFixture.signedBitWidth).max() ?? 1
        writer.writeUB(UInt32(nbits), count: 5)
        for field in fields {
            writer.writeSB(field, count: nbits)
        }
    }
}
