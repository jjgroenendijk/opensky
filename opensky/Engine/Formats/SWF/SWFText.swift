// DefineText (11) / DefineText2 (33): static text blocks — a character id,
// bounds, a placement MATRIX, and a run of TEXTRECORDs that switch font, color,
// and pen position and then place glyphs by index with explicit advances.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 10
// "Fonts and Text" — DefineText/DefineText2 (pp. 173-174), TEXTRECORD and
// GLYPHENTRY (pp. 174-175). DefineText2 stores RGBA where DefineText stores
// RGB. Documented in docs/formats/swf.md.

import Foundation

nonisolated enum SWFTextError: Error, Equatable {
    /// Tag code is not DefineText (11) or DefineText2 (33).
    case unsupportedTag(UInt16)
}

/// One placed glyph in a TEXTRECORD: an index into the current font's glyph
/// table and the advance (twips) added to the pen after drawing it.
nonisolated struct SWFGlyphEntry: Equatable {
    let glyphIndex: Int
    let advance: Int32
}

/// One TEXTRECORD. A record optionally changes the active font (with its text
/// height), color, and pen x/y offset (all twips), then places `glyphs`. Absent
/// state fields inherit the value carried by earlier records (spec p. 174).
nonisolated struct SWFTextRecord: Equatable {
    let fontID: UInt16?
    /// Font size in twips; present exactly when `fontID` is (StyleFlagsHasFont).
    let textHeight: UInt16?
    let color: SWFColor?
    let xOffset: Int32?
    let yOffset: Int32?
    let glyphs: [SWFGlyphEntry]
}

/// A decoded DefineText/DefineText2 character.
nonisolated struct SWFTextDefinition: Equatable {
    /// Tag codes this parser accepts.
    static let tagCodes: Set<UInt16> = [11, 33]

    let characterId: UInt16
    let bounds: SWFRect
    let matrix: SWFMatrix
    let records: [SWFTextRecord]

    /// Decodes a DefineText (11, RGB) or DefineText2 (33, RGBA) tag body.
    static func parse(tag: SWFTag) throws -> SWFTextDefinition {
        guard tag.code == 11 || tag.code == 33 else {
            throw SWFTextError.unsupportedTag(tag.code)
        }
        let hasAlpha = tag.code == 33
        var bits = SWFBitReader(tag.body)
        let characterId = try bits.readAlignedUInt16()
        let bounds = try SWFShapeParser.parseRect(&bits)
        let matrix = try SWFShapeParser.parseMatrix(&bits)
        let glyphBits = try Int(bits.readAlignedUInt8())
        let advanceBits = try Int(bits.readAlignedUInt8())
        let records = try parseRecords(
            &bits, hasAlpha: hasAlpha, glyphBits: glyphBits, advanceBits: advanceBits
        )
        return SWFTextDefinition(
            characterId: characterId, bounds: bounds, matrix: matrix, records: records
        )
    }

    /// Reads TEXTRECORDs until the zero terminator byte. Each record's flag
    /// byte is byte-aligned; the glyph entries that follow are bit-packed and
    /// the next record re-aligns.
    private static func parseRecords(
        _ bits: inout SWFBitReader,
        hasAlpha: Bool,
        glyphBits: Int,
        advanceBits: Int
    ) throws -> [SWFTextRecord] {
        var records: [SWFTextRecord] = []
        while true {
            let flags = try bits.readAlignedUInt8()
            if flags == 0 {
                return records
            }
            try records.append(parseRecord(
                &bits, flags: flags, hasAlpha: hasAlpha,
                glyphBits: glyphBits, advanceBits: advanceBits
            ))
        }
    }

    /// One TEXTRECORD body. Flag bits (MSB first): TextRecordType (1),
    /// Reserved UB[3], HasFont, HasColor, HasYOffset, HasXOffset. State fields
    /// follow in the order font id, color, x, y, text height (spec p. 174).
    private static func parseRecord(
        _ bits: inout SWFBitReader,
        flags: UInt8,
        hasAlpha: Bool,
        glyphBits: Int,
        advanceBits: Int
    ) throws -> SWFTextRecord {
        let hasFont = flags & 0x08 != 0
        var fontID: UInt16?
        var color: SWFColor?
        var xOffset: Int32?
        var yOffset: Int32?
        var textHeight: UInt16?
        if hasFont {
            fontID = try bits.readAlignedUInt16()
        }
        if flags & 0x04 != 0 {
            color = try SWFShapeParser.parseColor(&bits, hasAlpha: hasAlpha)
        }
        if flags & 0x01 != 0 {
            xOffset = try Int32(Int16(bitPattern: bits.readAlignedUInt16()))
        }
        if flags & 0x02 != 0 {
            yOffset = try Int32(Int16(bitPattern: bits.readAlignedUInt16()))
        }
        if hasFont {
            textHeight = try bits.readAlignedUInt16()
        }
        let glyphs = try parseGlyphEntries(&bits, glyphBits: glyphBits, advanceBits: advanceBits)
        return SWFTextRecord(
            fontID: fontID, textHeight: textHeight, color: color,
            xOffset: xOffset, yOffset: yOffset, glyphs: glyphs
        )
    }

    /// GlyphCount UI8, then that many GLYPHENTRYs of GlyphIndex UB[glyphBits] +
    /// GlyphAdvance SB[advanceBits], bit-packed without inter-entry alignment.
    private static func parseGlyphEntries(
        _ bits: inout SWFBitReader,
        glyphBits: Int,
        advanceBits: Int
    ) throws -> [SWFGlyphEntry] {
        let count = try Int(bits.readAlignedUInt8())
        var glyphs: [SWFGlyphEntry] = []
        glyphs.reserveCapacity(count)
        for _ in 0 ..< count {
            let index = try Int(bits.readUB(glyphBits))
            let advance = try bits.readSB(advanceBits)
            glyphs.append(SWFGlyphEntry(glyphIndex: index, advance: advance))
        }
        return glyphs
    }
}
