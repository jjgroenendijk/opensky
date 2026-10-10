// Decoded SWF font values: DefineFont2/3 glyph tables plus the companion tags
// (73, 74, 88). The on-disk packing lives in SWFFontParser.
// Layout and sources: docs/formats/swf-text.md.

import Foundation

nonisolated public enum SWFFontError: Error, Equatable, Sendable {
    /// Tag code is not DefineFont2 (48) or DefineFont3 (75).
    case unsupportedTag(UInt16)
    /// A glyph offset (or the code-table offset) points outside the tag body.
    case glyphOffsetOutOfRange(index: Int)
    /// A companion tag body ended before its fixed fields were read.
    case truncatedCompanionTag(UInt16)
}

/// The DefineFont2/3 style + encoding flag byte (spec p. 176). WideOffsets and
/// WideCodes drive the offset-table and code-table integer widths.
nonisolated public struct SWFFontFlags: Equatable, Sendable {
    public var hasLayout = false
    public var shiftJIS = false
    public var smallText = false
    public var ansi = false
    public var wideOffsets = false
    public var wideCodes = false
    public var italic = false
    public var bold = false
}

/// One glyph: its Unicode/ANSI character code (from the CodeTable) and its
/// shape as absolute-twip segments in the font's glyph-coordinate space. Fill
/// indices follow the glyph convention (0 = off, 1 = on) from
/// `SWFShapeDefinition.parseGlyphSegments`.
nonisolated public struct SWFFontGlyph: Equatable, Sendable {
    public let code: UInt16
    public let segments: [SWFShapeSegment]
}

/// One KERNINGRECORD (spec p. 180): the adjustment applied between an ordered
/// pair of character codes, in glyph-coordinate units.
nonisolated public struct SWFKerningRecord: Equatable, Sendable {
    public let code1: UInt16
    public let code2: UInt16
    public let adjustment: Int16
}

/// Per-glyph layout entry from the FontAdvanceTable + FontBoundsTable, present
/// only when `FontFlagsHasLayout` is set. `advance` and `bounds` are in glyph
/// units (see `SWFFontDefinition.unitsPerEM`).
nonisolated public struct SWFGlyphMetrics: Equatable, Sendable {
    public let advance: Int16
    public let bounds: SWFRect
}

/// Optional font-wide layout block (spec p. 176-180), retained when
/// `FontFlagsHasLayout` is set. Vertical metrics and per-glyph advances/bounds
/// are in glyph units; kerning adjustments likewise.
nonisolated public struct SWFFontLayout: Equatable, Sendable {
    public let ascent: Int16
    public let descent: Int16
    public let leading: Int16
    public let glyphMetrics: [SWFGlyphMetrics]
    public let kerning: [SWFKerningRecord]
}

/// A decoded DefineFont2 or DefineFont3 character. DefineFont3 stores glyph and
/// layout coordinates at 20x the resolution of DefineFont2 (spec p. 179); that
/// is captured by `unitsPerEM`, so a consumer scales any glyph coordinate by
/// `pixelSize / unitsPerEM` to reach pixels regardless of tag version.
nonisolated public struct SWFFontDefinition: Equatable, Sendable {
    /// Tag codes this parser accepts.
    public static let tagCodes: Set<UInt16> = [48, 75]

    public let fontID: UInt16
    /// True for DefineFont3 (20x-resolution glyph coordinates).
    public let isHighResolution: Bool
    public let flags: SWFFontFlags
    /// LANGCODE byte (0 = none); retained but not interpreted here.
    public let languageCode: UInt8
    public let name: String
    public let glyphs: [SWFFontGlyph]
    public let layout: SWFFontLayout?

    /// Glyph units per EM square: 1024 for DefineFont2, 20480 for DefineFont3.
    /// The EM square equals one font-size unit, so pixels-per-glyph-unit is
    /// `emPixelSize / unitsPerEM`.
    public var unitsPerEM: Int {
        isHighResolution ? 1024 * 20 : 1024
    }

    /// First glyph index whose CodeTable entry equals `code`, or nil. The
    /// CodeTable is ascending, but a linear scan is fine for the few-hundred
    /// glyph fonts in play and keeps the value type free of derived caches.
    public func glyphIndex(forCode code: UInt16) -> Int? {
        glyphs.firstIndex { $0.code == code }
    }
}

/// DefineFontAlignZones (73), decoded minimally (spec pp. 180-181): the target
/// font id and the CSM table hint. The per-glyph ZONERECORD table needs the
/// referenced font's glyph count to size and is retained raw rather than
/// decoded — OpenSky's CoreGraphics rasterizer does not use FlashType hinting.
nonisolated public struct SWFFontAlignZones: Equatable, Sendable {
    public let fontID: UInt16
    /// CSMTableHint UB[2]: 0 = thin, 1 = medium, 2 = thick (spec p. 181).
    public let csmTableHint: UInt8
    /// The undecoded ZONERECORD table bytes, kept for completeness.
    public let rawZoneTable: Data
}

/// CSMTextSettings (74), decoded (spec p. 181) and retained. OpenSky renders
/// text through its own CoreGraphics coverage path, so the anti-alias grid-fit
/// and thickness/sharpness hints are parsed-and-ignored.
nonisolated public struct SWFCSMTextSettings: Equatable, Sendable {
    public let textID: UInt16
    public let useFlashType: UInt8
    public let gridFit: UInt8
    public let thickness: Float
    public let sharpness: Float
}

/// DefineFontName (88): the font's full human name and copyright (spec p. 182).
nonisolated public struct SWFFontName: Equatable, Sendable {
    public let fontID: UInt16
    public let name: String
    public let copyright: String
}
