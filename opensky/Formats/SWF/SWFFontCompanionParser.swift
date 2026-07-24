// Minimal decoders for the font companion tags that accompany DefineFont2/3 in
// vanilla movies: DefineFontAlignZones (73), CSMTextSettings (74), and
// DefineFontName (88). OpenSky rasterizes glyphs through its own CoreGraphics
// coverage path, so the FlashType hinting these tags carry is parsed-and-
// retained rather than applied.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 10
// (pp. 180-182). Documented in docs/formats/swf.md.

import Foundation

nonisolated enum SWFFontCompanionParser {
    /// DefineFontAlignZones (73): FontID UI16, CSMTableHint UB[2] + Reserved
    /// UB[6], then a ZONERECORD per glyph. The zone table needs the referenced
    /// font's glyph count to size, so it is retained raw (see type doc).
    static func parseAlignZones(tag: SWFTag) throws -> SWFFontAlignZones {
        var reader = BinaryReader(tag.body)
        guard reader.bytesRemaining >= 3 else {
            throw SWFFontError.truncatedCompanionTag(tag.code)
        }
        let fontID = try reader.readUInt16()
        let hintByte = try reader.readUInt8()
        let rawZoneTable = try reader.read(count: reader.bytesRemaining)
        return SWFFontAlignZones(
            fontID: fontID,
            csmTableHint: (hintByte >> 6) & 0x03,
            rawZoneTable: rawZoneTable
        )
    }

    /// CSMTextSettings (74): TextID UI16, UseFlashType UB[2] + GridFit UB[3] +
    /// Reserved UB[3], Thickness FLOAT32, Sharpness FLOAT32, Reserved UI8.
    static func parseCSMTextSettings(tag: SWFTag) throws -> SWFCSMTextSettings {
        var reader = BinaryReader(tag.body)
        guard reader.bytesRemaining >= 11 else {
            throw SWFFontError.truncatedCompanionTag(tag.code)
        }
        let textID = try reader.readUInt16()
        let settingsByte = try reader.readUInt8()
        let thickness = try reader.readFloat32()
        let sharpness = try reader.readFloat32()
        return SWFCSMTextSettings(
            textID: textID,
            useFlashType: (settingsByte >> 6) & 0x03,
            gridFit: (settingsByte >> 3) & 0x07,
            thickness: thickness,
            sharpness: sharpness
        )
    }

    /// DefineFontName (88): FontID UI16, FontName STRING, FontCopyright STRING.
    /// Both strings are null-terminated UTF-8 (SWF 6+).
    static func parseFontName(tag: SWFTag) throws -> SWFFontName {
        var reader = BinaryReader(tag.body)
        let fontID = try reader.readUInt16()
        let name = try reader.readZString(encoding: .utf8)
        let copyright = try reader.readZString(encoding: .utf8)
        return SWFFontName(fontID: fontID, name: name, copyright: copyright)
    }
}
