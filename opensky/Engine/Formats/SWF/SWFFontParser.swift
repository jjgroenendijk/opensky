// Byte/bit-level decoding of the SWF font tags: DefineFont2 (48),
// DefineFont3 (75), and the companion tags DefineFontAlignZones (73),
// CSMTextSettings (74), and DefineFontName (88).
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 10
// "Fonts and Text" (pp. 176-182). The tag body mixes byte-aligned integers
// (little-endian) with the bit-packed glyph SHAPEs; glyph shapes are located
// through the OffsetTable rather than parsed sequentially, so any per-glyph
// padding is irrelevant. Alignment follows the shape parser's observed rule
// (byte-align each bit run) documented in docs/formats/swf.md.

import Foundation

nonisolated enum SWFFontParser {
    /// Decodes a DefineFont2 (48) or DefineFont3 (75) tag body.
    static func parse(tag: SWFTag) throws -> SWFFontDefinition {
        guard tag.code == 48 || tag.code == 75 else {
            throw SWFFontError.unsupportedTag(tag.code)
        }
        let body = tag.body
        var reader = BinaryReader(body)
        let fontID = try reader.readUInt16()
        let flags = try parseFlags(reader.readUInt8())
        let languageCode = try reader.readUInt8()
        let nameLength = try Int(reader.readUInt8())
        let nameBytes = try reader.read(count: nameLength)
        let name = decodeFontName(nameBytes)
        let glyphCount = try Int(reader.readUInt16())

        // A device-font placeholder carries no glyphs; vanilla encoders then
        // omit the offset table, code table, and layout entirely (observed in
        // hudmenu.swf). There is nothing to render, so return early.
        if glyphCount == 0 {
            return SWFFontDefinition(
                fontID: fontID, isHighResolution: tag.code == 75, flags: flags,
                languageCode: languageCode, name: name, glyphs: [], layout: nil
            )
        }

        let offsetTableStart = reader.offset
        let offsets = try readOffsetTable(&reader, glyphCount: glyphCount, wide: flags.wideOffsets)
        let codeTableStart = offsetTableStart + offsets.codeTableOffset
        let glyphShapes = try parseGlyphShapes(
            body: body,
            offsetTableStart: offsetTableStart,
            glyphOffsets: offsets.glyphOffsets,
            codeTableOffset: offsets.codeTableOffset
        )
        var codeReader = BinaryReader(body, offset: codeTableStart)
        let codes = try readCodeTable(&codeReader, glyphCount: glyphCount, wide: flags.wideCodes)
        let glyphs = zip(codes, glyphShapes).map { SWFFontGlyph(code: $0, segments: $1) }

        var layout: SWFFontLayout?
        if flags.hasLayout {
            layout = try parseLayout(
                body: body,
                start: codeReader.offset,
                glyphCount: glyphCount,
                wideCodes: flags.wideCodes
            )
        }
        return SWFFontDefinition(
            fontID: fontID,
            isHighResolution: tag.code == 75,
            flags: flags,
            languageCode: languageCode,
            name: name,
            glyphs: glyphs,
            layout: layout
        )
    }

    /// FontFlags byte (spec p. 176), MSB first: HasLayout, ShiftJIS, SmallText,
    /// ANSI, WideOffsets, WideCodes, Italic, Bold.
    private static func parseFlags(_ byte: UInt8) -> SWFFontFlags {
        SWFFontFlags(
            hasLayout: byte & 0x80 != 0,
            shiftJIS: byte & 0x40 != 0,
            smallText: byte & 0x20 != 0,
            ansi: byte & 0x10 != 0,
            wideOffsets: byte & 0x08 != 0,
            wideCodes: byte & 0x04 != 0,
            italic: byte & 0x02 != 0,
            bold: byte & 0x01 != 0
        )
    }

    /// The font name is a fixed-length byte run; ANSI fonts use CP1252, others
    /// are treated as UTF-8. Falls back to CP1252 so a stray byte never fails.
    private static func decodeFontName(_ bytes: Data) -> String {
        let trimmed = bytes.prefix { $0 != 0 }
        if let utf8 = String(data: trimmed, encoding: .utf8) {
            return utf8
        }
        return String(data: trimmed, encoding: .windowsCP1252) ?? ""
    }

    private struct OffsetTable {
        let glyphOffsets: [Int]
        let codeTableOffset: Int
    }

    /// OffsetTable of `glyphCount` entries plus the trailing CodeTableOffset,
    /// each UI32 (WideOffsets) or UI16, measured from the table start.
    private static func readOffsetTable(
        _ reader: inout BinaryReader,
        glyphCount: Int,
        wide: Bool
    ) throws -> OffsetTable {
        func next() throws -> Int {
            wide ? try Int(reader.readUInt32()) : try Int(reader.readUInt16())
        }
        var glyphOffsets: [Int] = []
        glyphOffsets.reserveCapacity(glyphCount)
        for _ in 0 ..< glyphCount {
            try glyphOffsets.append(next())
        }
        return try OffsetTable(glyphOffsets: glyphOffsets, codeTableOffset: next())
    }

    /// Slices each glyph's SHAPE from the body using the offset table (offsets
    /// are relative to the table start) and parses it as a bare glyph shape.
    private static func parseGlyphShapes(
        body: Data,
        offsetTableStart: Int,
        glyphOffsets: [Int],
        codeTableOffset: Int
    ) throws -> [[SWFShapeSegment]] {
        var shapes: [[SWFShapeSegment]] = []
        shapes.reserveCapacity(glyphOffsets.count)
        for index in glyphOffsets.indices {
            let start = offsetTableStart + glyphOffsets[index]
            let nextOffset = index + 1 < glyphOffsets.count
                ? glyphOffsets[index + 1]
                : codeTableOffset
            let end = offsetTableStart + nextOffset
            guard start >= 0, end >= start, end <= body.count else {
                throw SWFFontError.glyphOffsetOutOfRange(index: index)
            }
            let slice = body.subdata(in: (body.startIndex + start) ..< (body.startIndex + end))
            var bits = SWFBitReader(slice)
            try shapes.append(SWFShapeDefinition.parseGlyphSegments(&bits))
        }
        return shapes
    }

    /// CodeTable of `glyphCount` character codes, UI16 (WideCodes) or UI8.
    private static func readCodeTable(
        _ reader: inout BinaryReader,
        glyphCount: Int,
        wide: Bool
    ) throws -> [UInt16] {
        var codes: [UInt16] = []
        codes.reserveCapacity(glyphCount)
        for _ in 0 ..< glyphCount {
            try codes.append(wide ? reader.readUInt16() : UInt16(reader.readUInt8()))
        }
        return codes
    }

    /// The FontFlagsHasLayout block (spec pp. 176-180): vertical metrics, the
    /// per-glyph advance + bounds tables, and the kerning table. Driven by a
    /// bit reader because the FontBoundsTable holds bit-packed RECTs.
    private static func parseLayout(
        body: Data,
        start: Int,
        glyphCount: Int,
        wideCodes: Bool
    ) throws -> SWFFontLayout {
        let slice = body.subdata(in: (body.startIndex + start) ..< body.endIndex)
        var bits = SWFBitReader(slice)
        let ascent = try readSI16(&bits)
        let descent = try readSI16(&bits)
        let leading = try readSI16(&bits)
        var advances: [Int16] = []
        advances.reserveCapacity(glyphCount)
        for _ in 0 ..< glyphCount {
            try advances.append(readSI16(&bits))
        }
        var glyphMetrics: [SWFGlyphMetrics] = []
        glyphMetrics.reserveCapacity(glyphCount)
        for index in 0 ..< glyphCount {
            let bounds = try SWFShapeParser.parseRect(&bits)
            glyphMetrics.append(SWFGlyphMetrics(advance: advances[index], bounds: bounds))
        }
        let kerning = try parseKerning(&bits, wideCodes: wideCodes)
        return SWFFontLayout(
            ascent: ascent, descent: descent, leading: leading,
            glyphMetrics: glyphMetrics, kerning: kerning
        )
    }

    private static func parseKerning(
        _ bits: inout SWFBitReader,
        wideCodes: Bool
    ) throws -> [SWFKerningRecord] {
        let count = try Int(bits.readAlignedUInt16())
        var records: [SWFKerningRecord] = []
        records.reserveCapacity(min(count, 4096))
        for _ in 0 ..< count {
            let code1: UInt16 = try wideCodes
                ? bits.readAlignedUInt16() : UInt16(bits.readAlignedUInt8())
            let code2: UInt16 = try wideCodes
                ? bits.readAlignedUInt16() : UInt16(bits.readAlignedUInt8())
            let adjustment = try readSI16(&bits)
            records.append(SWFKerningRecord(code1: code1, code2: code2, adjustment: adjustment))
        }
        return records
    }

    /// Byte-aligned little-endian SI16.
    private static func readSI16(_ bits: inout SWFBitReader) throws -> Int16 {
        try Int16(bitPattern: bits.readAlignedUInt16())
    }
}
