// Synthetic DefineText/DefineText2/DefineEditText tag-body builders for the
// static-text parser tests. Assembled bit-by-bit in code following the Adobe
// SWF File Format Specification v19 chapter 10 layouts — never extracted game
// files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import OpenSkyFormats

/// Assembles a DefineText (11) / DefineText2 (33) tag body.
public struct SWFTextBodyBuilder: Sendable {
    /// One glyph placement inside a text record.
    public struct Glyph: Sendable {
        public let index: Int
        public let advance: Int32

        public init(index: Int, advance: Int32) {
            self.index = index
            self.advance = advance
        }
    }

    /// One TEXTRECORD: optional state changes then glyph placements.
    public struct Record: Sendable {
        public var fontID: UInt16?
        public var textHeight: UInt16?
        public var color: SWFColor?
        public var xOffset: Int16?
        public var yOffset: Int16?
        public var glyphs: [Glyph] = []

        public init(
            fontID: UInt16? = nil,
            textHeight: UInt16? = nil,
            color: SWFColor? = nil,
            xOffset: Int16? = nil,
            yOffset: Int16? = nil,
            glyphs: [Glyph] = []
        ) {
            self.fontID = fontID
            self.textHeight = textHeight
            self.color = color
            self.xOffset = xOffset
            self.yOffset = yOffset
            self.glyphs = glyphs
        }
    }

    public var characterId: UInt16 = 1
    public var bounds = SWFRect(xMin: 0, xMax: 2000, yMin: 0, yMax: 400)
    public var translateX: Int32 = 0
    public var translateY: Int32 = 0
    /// DefineText2 stores RGBA colors; DefineText stores RGB.
    public var rgba = false
    public var glyphBits = 8
    public var advanceBits = 12
    public var records: [Record] = []

    public var writer = SWFBitWriter()

    public mutating func build() -> Data {
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

    public init(
        characterId: UInt16 = 1,
        bounds: SWFRect = SWFRect(xMin: 0, xMax: 2000, yMin: 0, yMax: 400),
        translateX: Int32 = 0,
        translateY: Int32 = 0,
        rgba: Bool = false,
        glyphBits: Int = 8,
        advanceBits: Int = 12,
        records: [Record] = [],
        writer: SWFBitWriter = SWFBitWriter()
    ) {
        self.characterId = characterId
        self.bounds = bounds
        self.translateX = translateX
        self.translateY = translateY
        self.rgba = rgba
        self.glyphBits = glyphBits
        self.advanceBits = advanceBits
        self.records = records
        self.writer = writer
    }
}

/// Assembles a DefineEditText (37) tag body.
public struct SWFEditTextBodyBuilder: Sendable {
    public var characterId: UInt16 = 1
    public var bounds = SWFRect(xMin: 0, xMax: 4000, yMin: 0, yMax: 800)
    public var flags = SWFEditTextFlags()
    public var fontID: UInt16?
    public var fontClass: String?
    public var fontHeight: UInt16?
    public var color: SWFColor?
    public var maxLength: UInt16?
    public var layout: SWFEditTextLayout?
    public var variableName = ""
    public var initialText: String?

    public var writer = SWFBitWriter()

    public mutating func build() -> Data {
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

    public init(
        characterId: UInt16 = 1,
        bounds: SWFRect = SWFRect(xMin: 0, xMax: 4000, yMin: 0, yMax: 800),
        flags: SWFEditTextFlags = SWFEditTextFlags(),
        fontID: UInt16? = nil,
        fontClass: String? = nil,
        fontHeight: UInt16? = nil,
        color: SWFColor? = nil,
        maxLength: UInt16? = nil,
        layout: SWFEditTextLayout? = nil,
        variableName: String = "",
        initialText: String? = nil,
        writer: SWFBitWriter = SWFBitWriter()
    ) {
        self.characterId = characterId
        self.bounds = bounds
        self.flags = flags
        self.fontID = fontID
        self.fontClass = fontClass
        self.fontHeight = fontHeight
        self.color = color
        self.maxLength = maxLength
        self.layout = layout
        self.variableName = variableName
        self.initialText = initialText
        self.writer = writer
    }
}
