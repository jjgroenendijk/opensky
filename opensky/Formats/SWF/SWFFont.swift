// Value types for decoded SWF fonts: DefineFont2 (48) / DefineFont3 (75) glyph
// tables plus the minimally-decoded companion tags DefineFontAlignZones (73),
// CSMTextSettings (74), and DefineFontName (88). The on-disk bit/byte packing
// lives in SWFFontParser; these types are decoupled from the layout.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 10
// "Fonts and Text" — DefineFont2/DefineFont3 (pp. 176-180),
// DefineFontAlignZones (pp. 180-181), CSMTextSettings (p. 181),
// DefineFontName (p. 182). Documented in docs/formats/swf.md.

import Foundation

nonisolated enum SWFFontError: Error, Equatable {
    /// Tag code is not DefineFont2 (48) or DefineFont3 (75).
    case unsupportedTag(UInt16)
    /// A glyph offset (or the code-table offset) points outside the tag body.
    case glyphOffsetOutOfRange(index: Int)
    /// A companion tag body ended before its fixed fields were read.
    case truncatedCompanionTag(UInt16)
}

/// The DefineFont2/3 style + encoding flag byte (spec p. 176). WideOffsets and
/// WideCodes drive the offset-table and code-table integer widths.
nonisolated struct SWFFontFlags: Equatable {
    var hasLayout = false
    var shiftJIS = false
    var smallText = false
    var ansi = false
    var wideOffsets = false
    var wideCodes = false
    var italic = false
    var bold = false
}

/// One glyph: its Unicode/ANSI character code (from the CodeTable) and its
/// shape as absolute-twip segments in the font's glyph-coordinate space. Fill
/// indices follow the glyph convention (0 = off, 1 = on) from
/// `SWFShapeDefinition.parseGlyphSegments`.
nonisolated struct SWFFontGlyph: Equatable {
    let code: UInt16
    let segments: [SWFShapeSegment]
}

/// One KERNINGRECORD (spec p. 180): the adjustment applied between an ordered
/// pair of character codes, in glyph-coordinate units.
nonisolated struct SWFKerningRecord: Equatable {
    let code1: UInt16
    let code2: UInt16
    let adjustment: Int16
}

/// Per-glyph layout entry from the FontAdvanceTable + FontBoundsTable, present
/// only when `FontFlagsHasLayout` is set. `advance` and `bounds` are in glyph
/// units (see `SWFFontDefinition.unitsPerEM`).
nonisolated struct SWFGlyphMetrics: Equatable {
    let advance: Int16
    let bounds: SWFRect
}

/// Optional font-wide layout block (spec p. 176-180), retained when
/// `FontFlagsHasLayout` is set. Vertical metrics and per-glyph advances/bounds
/// are in glyph units; kerning adjustments likewise.
nonisolated struct SWFFontLayout: Equatable {
    let ascent: Int16
    let descent: Int16
    let leading: Int16
    let glyphMetrics: [SWFGlyphMetrics]
    let kerning: [SWFKerningRecord]
}

/// A decoded DefineFont2 or DefineFont3 character. DefineFont3 stores glyph and
/// layout coordinates at 20x the resolution of DefineFont2 (spec p. 179); that
/// is captured by `unitsPerEM`, so a consumer scales any glyph coordinate by
/// `pixelSize / unitsPerEM` to reach pixels regardless of tag version.
nonisolated struct SWFFontDefinition: Equatable {
    /// Tag codes this parser accepts.
    static let tagCodes: Set<UInt16> = [48, 75]

    let fontID: UInt16
    /// True for DefineFont3 (20x-resolution glyph coordinates).
    let isHighResolution: Bool
    let flags: SWFFontFlags
    /// LANGCODE byte (0 = none); retained but not interpreted here.
    let languageCode: UInt8
    let name: String
    let glyphs: [SWFFontGlyph]
    let layout: SWFFontLayout?

    /// Glyph units per EM square: 1024 for DefineFont2, 20480 for DefineFont3.
    /// The EM square equals one font-size unit, so pixels-per-glyph-unit is
    /// `emPixelSize / unitsPerEM`.
    var unitsPerEM: Int {
        isHighResolution ? 1024 * 20 : 1024
    }

    /// First glyph index whose CodeTable entry equals `code`, or nil. The
    /// CodeTable is ascending, but a linear scan is fine for the few-hundred
    /// glyph fonts in play and keeps the value type free of derived caches.
    func glyphIndex(forCode code: UInt16) -> Int? {
        glyphs.firstIndex { $0.code == code }
    }
}

/// DefineFontAlignZones (73), decoded minimally (spec pp. 180-181): the target
/// font id and the CSM table hint. The per-glyph ZONERECORD table needs the
/// referenced font's glyph count to size and is retained raw rather than
/// decoded — OpenSky's CoreGraphics rasterizer does not use FlashType hinting.
nonisolated struct SWFFontAlignZones: Equatable {
    let fontID: UInt16
    /// CSMTableHint UB[2]: 0 = thin, 1 = medium, 2 = thick (spec p. 181).
    let csmTableHint: UInt8
    /// The undecoded ZONERECORD table bytes, kept for completeness.
    let rawZoneTable: Data
}

/// CSMTextSettings (74), decoded (spec p. 181) and retained. OpenSky renders
/// text through its own CoreGraphics coverage path, so the anti-alias grid-fit
/// and thickness/sharpness hints are parsed-and-ignored.
nonisolated struct SWFCSMTextSettings: Equatable {
    let textID: UInt16
    let useFlashType: UInt8
    let gridFit: UInt8
    let thickness: Float
    let sharpness: Float
}

/// DefineFontName (88): the font's full human name and copyright (spec p. 182).
nonisolated struct SWFFontName: Equatable {
    let fontID: UInt16
    let name: String
    let copyright: String
}
