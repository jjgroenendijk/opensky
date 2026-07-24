// Twip-space text layout tests (milestone 8.2.4): static-text record state
// inheritance and pen advances, edit-text line breaking, greedy word wrap,
// alignment, kerning, and missing-glyph accounting. Synthetic fonts built
// with SWFFontBodyBuilder.

import Foundation
@testable import opensky
import Testing

struct SWFTextLayoutTests {
    /// A DefineFont2 with glyphs for "A" (advance 600), "B" (advance 500),
    /// and space (advance 300), layout ascent 800 / descent 200, and one
    /// kerning pair AB = -100 (all glyph units, EM 1024).
    private static func makeFont() throws -> SWFFontDefinition {
        var builder = SWFFontBodyBuilder()
        builder.fontID = 1
        builder.flags.hasLayout = true
        builder.codes = [65, 66, 32]
        builder.shapes = [
            SWFFontBodyBuilder.triangleGlyphShape(size: 700),
            SWFFontBodyBuilder.triangleGlyphShape(size: 600),
            SWFFontBodyBuilder.glyphShape { _ in }
        ]
        builder.layout = SWFFontBodyBuilder.Layout(
            ascent: 800,
            descent: 200,
            leading: 0,
            advances: [600, 500, 300],
            bounds: [
                SWFRect(xMin: 0, xMax: 700, yMin: -700, yMax: 0),
                SWFRect(xMin: 0, xMax: 600, yMin: -600, yMax: 0),
                SWFRect(xMin: 0, xMax: 0, yMin: 0, yMax: 0)
            ],
            kerning: [SWFKerningRecord(code1: 65, code2: 66, adjustment: -100)]
        )
        return try SWFFontParser.parse(tag: SWFTag(code: 48, body: builder.build()))
    }

    private static func makeEditText(
        text: String,
        bounds: SWFRect = SWFRect(xMin: 0, xMax: 4000, yMin: 0, yMax: 2000),
        wordWrap: Bool = false,
        align: UInt8? = nil
    ) throws -> SWFEditText {
        var builder = SWFEditTextBodyBuilder()
        builder.bounds = bounds
        builder.flags.hasText = true
        builder.flags.hasFont = true
        builder.flags.multiline = true
        builder.flags.wordWrap = wordWrap
        builder.fontID = 1
        builder.fontHeight = 1024 // scale 1: glyph units == twips
        builder.initialText = text
        if let align {
            builder.flags.hasLayout = true
            builder.layout = SWFEditTextLayout(
                align: align, leftMargin: 0, rightMargin: 0, indent: 0, leading: 0
            )
        }
        return try SWFEditText.parse(tag: SWFTag(code: 37, body: builder.build()))
    }

    @Test func staticTextAdvancesPenAndInheritsState() throws {
        var builder = SWFTextBodyBuilder()
        builder.records = [
            SWFTextBodyBuilder.Record(
                fontID: 1,
                textHeight: 240,
                color: SWFColor(red: 255, green: 0, blue: 0, alpha: 255),
                xOffset: 100,
                yOffset: 300,
                glyphs: [
                    SWFTextBodyBuilder.Glyph(index: 0, advance: 200),
                    SWFTextBodyBuilder.Glyph(index: 1, advance: 180)
                ]
            ),
            // No font/color change: state inherits, new x offset resets pen.
            SWFTextBodyBuilder.Record(
                xOffset: 900,
                glyphs: [SWFTextBodyBuilder.Glyph(index: 0, advance: 150)]
            )
        ]
        let text = try SWFTextDefinition.parse(tag: SWFTag(code: 11, body: builder.build()))
        let layout = SWFTextLayout.staticText(text)
        #expect(layout.runs.count == 2)
        let first = layout.runs[0]
        #expect(first.fontID == 1)
        #expect(first.emTwips == 240)
        #expect(first.glyphs.map(\.x) == [100, 300])
        #expect(first.glyphs.map(\.y) == [300, 300])
        let second = layout.runs[1]
        #expect(second.fontID == 1)
        #expect(second.color == first.color)
        #expect(second.glyphs.map(\.x) == [900])
    }

    @Test func editTextLaysOutGlyphsWithKerning() throws {
        let font = try Self.makeFont()
        let text = try Self.makeEditText(text: "AB")
        let layout = SWFTextLayout.editText(text, font: font)
        #expect(layout.missingGlyphs == 0)
        let run = try #require(layout.runs.first)
        #expect(run.emTwips == 1024)
        #expect(run.glyphs.count == 2)
        // First baseline: bounds top + ascent (scale 1 -> 800 twips).
        #expect(run.glyphs[0].y == 800)
        #expect(run.glyphs[0].x == 0)
        // Kerned pen: advance 600 + kerning -100.
        #expect(run.glyphs[1].x == 500)
    }

    @Test func newlinesAdvanceTheBaseline() throws {
        let font = try Self.makeFont()
        let text = try Self.makeEditText(text: "A\nB")
        let layout = SWFTextLayout.editText(text, font: font)
        let run = try #require(layout.runs.first)
        #expect(run.glyphs.count == 2)
        // Line advance = ascent + descent + leading = 1000 twips at scale 1.
        #expect(run.glyphs[1].y - run.glyphs[0].y == 1000)
        #expect(run.glyphs[1].x == 0)
    }

    @Test func wordWrapBreaksAtSpaces() throws {
        let font = try Self.makeFont()
        // "AB AB AB": word width 1100 (600 - 100 kern + 500? no kern across
        // space) -> with bounds 2600 wide two words fit per line.
        let text = try Self.makeEditText(
            text: "AB AB AB",
            bounds: SWFRect(xMin: 0, xMax: 2600, yMin: 0, yMax: 4000),
            wordWrap: true
        )
        let layout = SWFTextLayout.editText(text, font: font)
        let run = try #require(layout.runs.first)
        let baselines = Set(run.glyphs.map(\.y))
        #expect(baselines.count == 2)
        // The wrapped word restarts at the left edge.
        let secondLineY = baselines.max() ?? 0
        let secondLineXs = run.glyphs.filter { $0.y == secondLineY }.map(\.x)
        #expect(secondLineXs.first == 0)
    }

    @Test func centerAlignmentCentersTheLine() throws {
        let font = try Self.makeFont()
        let text = try Self.makeEditText(
            text: "A",
            bounds: SWFRect(xMin: 0, xMax: 2000, yMin: 0, yMax: 2000),
            align: 2
        )
        let layout = SWFTextLayout.editText(text, font: font)
        let run = try #require(layout.runs.first)
        // Line width 600 in a 2000 field -> starts at 700.
        #expect(run.glyphs.first?.x == 700)
    }

    @Test func rightAlignmentFlushesTheLineRight() throws {
        let font = try Self.makeFont()
        let text = try Self.makeEditText(
            text: "A",
            bounds: SWFRect(xMin: 0, xMax: 2000, yMin: 0, yMax: 2000),
            align: 1
        )
        let layout = SWFTextLayout.editText(text, font: font)
        let run = try #require(layout.runs.first)
        #expect(run.glyphs.first?.x == 1400)
    }

    @Test func missingGlyphsAreCountedAndSkipped() throws {
        let font = try Self.makeFont()
        let text = try Self.makeEditText(text: "AZB")
        let layout = SWFTextLayout.editText(text, font: font)
        #expect(layout.missingGlyphs == 1)
        #expect(layout.runs.first?.glyphs.count == 2)
    }

    @Test func emptyContentProducesNoRuns() throws {
        let font = try Self.makeFont()
        var builder = SWFEditTextBodyBuilder()
        builder.flags.hasFont = true
        builder.fontID = 1
        builder.fontHeight = 240
        let text = try SWFEditText.parse(tag: SWFTag(code: 37, body: builder.build()))
        let layout = SWFTextLayout.editText(text, font: font)
        #expect(layout.runs.isEmpty)
    }
}
