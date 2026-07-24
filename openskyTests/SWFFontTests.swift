// Unit tests for DefineFont2 (48) / DefineFont3 (75) decoding and the font
// companion tags. All fixtures are synthetic, built through SWFFontBodyBuilder.

import Foundation
@testable import opensky
import Testing

struct SWFFontTests {
    /// A two-glyph DefineFont2 body: triangles at codes 'A' (65) and 'B' (66).
    private func twoGlyphBuilder() -> SWFFontBodyBuilder {
        var builder = SWFFontBodyBuilder()
        builder.fontID = 3
        builder.name = "Futura"
        builder.flags.bold = true
        builder.codes = [65, 66]
        builder.shapes = [
            SWFFontBodyBuilder.triangleGlyphShape(size: 200),
            SWFFontBodyBuilder.triangleGlyphShape(size: 300)
        ]
        return builder
    }

    @Test func parsesDefineFont2GlyphsAndCodeTable() throws {
        let font = try SWFFontParser.parse(
            tag: SWFTag(code: 48, body: twoGlyphBuilder().build())
        )
        #expect(font.fontID == 3)
        #expect(font.name == "Futura")
        #expect(font.flags.bold)
        #expect(!font.isHighResolution)
        #expect(font.unitsPerEM == 1024)
        #expect(font.glyphs.count == 2)
        #expect(font.glyphs.map(\.code) == [65, 66])
        #expect(font.glyphIndex(forCode: 66) == 1)
        #expect(font.glyphIndex(forCode: 99) == nil)
        let first = font.glyphs[0]
        #expect(first.segments.count == 3)
        #expect(first.segments[0].fromX == 0)
        #expect(first.segments[0].edge == .line(toX: 200, toY: 0))
        #expect(first.segments[0].fillStyle1 == 1)
        #expect(font.glyphs[1].segments[0].edge == .line(toX: 300, toY: 0))
        #expect(font.layout == nil)
    }

    @Test func parsesDefineFont3AsHighResolution() throws {
        var builder = twoGlyphBuilder()
        builder.name = "FuturaHi"
        let font = try SWFFontParser.parse(tag: SWFTag(code: 75, body: builder.build()))
        #expect(font.isHighResolution)
        #expect(font.unitsPerEM == 1024 * 20)
        // Glyph coordinates are stored verbatim; only unitsPerEM differs, so a
        // consumer scales identical coordinates by 1/20 the amount vs Font2.
        #expect(font.glyphs[0].segments[0].edge == .line(toX: 200, toY: 0))
    }

    @Test func parsesWideOffsetsAndWideCodes() throws {
        var builder = twoGlyphBuilder()
        builder.flags.wideOffsets = true
        builder.flags.wideCodes = true
        builder.codes = [0x2019, 0x00E9] // a wide code that needs 16 bits
        let font = try SWFFontParser.parse(tag: SWFTag(code: 48, body: builder.build()))
        #expect(font.glyphs.map(\.code) == [0x2019, 0x00E9])
        #expect(font.glyphs.count == 2)
        #expect(font.glyphs[1].segments[0].edge == .line(toX: 300, toY: 0))
    }

    @Test func parsesLayoutWithAdvancesBoundsAndKerning() throws {
        var builder = twoGlyphBuilder()
        builder.flags.hasLayout = true
        builder.layout = SWFFontBodyBuilder.Layout(
            ascent: 880, descent: 250, leading: 60,
            advances: [512, 640],
            bounds: [
                SWFRect(xMin: 0, xMax: 200, yMin: -200, yMax: 0),
                SWFRect(xMin: 0, xMax: 300, yMin: -300, yMax: 0)
            ],
            kerning: [SWFKerningRecord(code1: 65, code2: 66, adjustment: -40)]
        )
        let font = try SWFFontParser.parse(tag: SWFTag(code: 48, body: builder.build()))
        let layout = try #require(font.layout)
        #expect(layout.ascent == 880)
        #expect(layout.descent == 250)
        #expect(layout.leading == 60)
        #expect(layout.glyphMetrics.map(\.advance) == [512, 640])
        #expect(layout.glyphMetrics[1].bounds == SWFRect(xMin: 0, xMax: 300, yMin: -300, yMax: 0))
        #expect(layout.kerning == [SWFKerningRecord(code1: 65, code2: 66, adjustment: -40)])
    }

    @Test func parsesWideCodeKerningRecords() throws {
        var builder = twoGlyphBuilder()
        builder.flags.wideCodes = true
        builder.flags.hasLayout = true
        builder.codes = [0x2018, 0x2019]
        builder.layout = SWFFontBodyBuilder.Layout(
            advances: [400, 400],
            bounds: [
                SWFRect(xMin: 0, xMax: 0, yMin: 0, yMax: 0),
                SWFRect(xMin: 0, xMax: 0, yMin: 0, yMax: 0)
            ],
            kerning: [SWFKerningRecord(code1: 0x2018, code2: 0x2019, adjustment: 15)]
        )
        let font = try SWFFontParser.parse(tag: SWFTag(code: 75, body: builder.build()))
        #expect(font.layout?.kerning.first?.code1 == 0x2018)
        #expect(font.layout?.kerning.first?.adjustment == 15)
    }

    @Test func rejectsUnsupportedTag() {
        #expect(throws: SWFFontError.unsupportedTag(10)) {
            _ = try SWFFontParser.parse(tag: SWFTag(code: 10, body: Data()))
        }
    }

    @Test func rejectsTruncatedBody() {
        let body = twoGlyphBuilder().build()
        #expect(throws: (any Error).self) {
            _ = try SWFFontParser.parse(
                tag: SWFTag(code: 48, body: body.prefix(body.count - 3))
            )
        }
    }

    @Test func parsesDefineFontAlignZones() throws {
        var body = Data()
        body.appendUInt16(7)
        body.append(0x80) // CSMTableHint = 2 (thick) in the top two bits
        body.append(contentsOf: [0x11, 0x22, 0x33])
        let zones = try SWFFontCompanionParser.parseAlignZones(tag: SWFTag(code: 73, body: body))
        #expect(zones.fontID == 7)
        #expect(zones.csmTableHint == 2)
        #expect(zones.rawZoneTable == Data([0x11, 0x22, 0x33]))
    }

    @Test func parsesCSMTextSettings() throws {
        var body = Data()
        body.appendUInt16(9)
        body.append(0x40) // UseFlashType = 1, GridFit = 0
        body.appendFloat32(0.5)
        body.appendFloat32(-0.25)
        body.append(0) // reserved
        let settings = try SWFFontCompanionParser.parseCSMTextSettings(
            tag: SWFTag(code: 74, body: body)
        )
        #expect(settings.textID == 9)
        #expect(settings.useFlashType == 1)
        #expect(settings.thickness == 0.5)
        #expect(settings.sharpness == -0.25)
    }

    @Test func parsesDefineFontName() throws {
        var body = Data()
        body.appendUInt16(4)
        body.append(contentsOf: Array("Futura Std".utf8))
        body.append(0)
        body.append(contentsOf: Array("(c) Foundry".utf8))
        body.append(0)
        let fontName = try SWFFontCompanionParser.parseFontName(tag: SWFTag(code: 88, body: body))
        #expect(fontName.fontID == 4)
        #expect(fontName.name == "Futura Std")
        #expect(fontName.copyright == "(c) Foundry")
    }
}
