// Unit tests for DefineText (11) / DefineText2 (33) and DefineEditText (37)
// decoding. All fixtures are synthetic, built through the text body builders.

import Foundation
@testable import opensky
import Testing

struct SWFTextTests {
    private let white = SWFColor(red: 255, green: 255, blue: 255, alpha: 255)
    private let translucentRed = SWFColor(red: 255, green: 0, blue: 0, alpha: 128)

    @Test func parsesDefineTextWithMixedStyleRecords() throws {
        var builder = SWFTextBodyBuilder()
        builder.characterId = 12
        builder.translateX = 20
        builder.translateY = 40
        builder.records = [
            SWFTextBodyBuilder.Record(
                fontID: 3, textHeight: 240, color: white, xOffset: 10, yOffset: 200,
                glyphs: [
                    SWFTextBodyBuilder.Glyph(index: 0, advance: 120),
                    SWFTextBodyBuilder.Glyph(index: 5, advance: 96)
                ]
            ),
            // Second record only shifts the pen and places one glyph; font and
            // color inherit from the first (their state flags are unset).
            SWFTextBodyBuilder.Record(
                xOffset: -30,
                glyphs: [SWFTextBodyBuilder.Glyph(index: 9, advance: -50)]
            )
        ]

        let text = try SWFTextDefinition.parse(tag: SWFTag(code: 11, body: builder.build()))
        #expect(text.characterId == 12)
        #expect(text.matrix.translateX == 20)
        #expect(text.matrix.translateY == 40)
        #expect(text.records.count == 2)
        let first = text.records[0]
        #expect(first.fontID == 3)
        #expect(first.textHeight == 240)
        #expect(first.color == white) // RGB parses opaque
        #expect(first.xOffset == 10)
        #expect(first.yOffset == 200)
        #expect(first.glyphs == [
            SWFGlyphEntry(glyphIndex: 0, advance: 120),
            SWFGlyphEntry(glyphIndex: 5, advance: 96)
        ])
        let second = text.records[1]
        #expect(second.fontID == nil)
        #expect(second.color == nil)
        #expect(second.textHeight == nil)
        #expect(second.xOffset == -30)
        #expect(second.glyphs == [SWFGlyphEntry(glyphIndex: 9, advance: -50)])
    }

    @Test func parsesDefineText2Alpha() throws {
        var builder = SWFTextBodyBuilder()
        builder.rgba = true
        builder.records = [
            SWFTextBodyBuilder.Record(
                fontID: 1, textHeight: 200, color: translucentRed,
                glyphs: [SWFTextBodyBuilder.Glyph(index: 2, advance: 80)]
            )
        ]
        let text = try SWFTextDefinition.parse(tag: SWFTag(code: 33, body: builder.build()))
        #expect(text.records[0].color == translucentRed)
        #expect(text.records[0].color?.alpha == 128)
    }

    @Test func rejectsUnsupportedTextTag() {
        #expect(throws: SWFTextError.unsupportedTag(37)) {
            _ = try SWFTextDefinition.parse(tag: SWFTag(code: 37, body: Data()))
        }
    }

    @Test func parsesDefineEditTextWithFontColorAndText() throws {
        var builder = SWFEditTextBodyBuilder()
        builder.characterId = 20
        builder.flags.hasText = true
        builder.flags.wordWrap = true
        builder.flags.multiline = true
        builder.flags.readOnly = true
        builder.flags.hasFont = true
        builder.flags.hasTextColor = true
        builder.flags.hasLayout = true
        builder.fontID = 3
        builder.fontHeight = 240
        builder.color = translucentRed
        builder.layout = SWFEditTextLayout(
            align: 1, leftMargin: 40, rightMargin: 40, indent: 0, leading: 20
        )
        builder.variableName = "PlayerName"
        builder.initialText = "Dragonborn"

        let edit = try SWFEditText.parse(tag: SWFTag(code: 37, body: builder.build()))
        #expect(edit.characterId == 20)
        #expect(edit.flags.hasText)
        #expect(edit.flags.wordWrap)
        #expect(edit.flags.multiline)
        #expect(edit.flags.readOnly)
        #expect(!edit.flags.password)
        #expect(edit.fontID == 3)
        #expect(edit.fontHeight == 240)
        #expect(edit.color == translucentRed)
        #expect(edit.layout?.align == 1)
        #expect(edit.layout?.leftMargin == 40)
        #expect(edit.layout?.leading == 20)
        #expect(edit.variableName == "PlayerName")
        #expect(edit.initialText == "Dragonborn")
        #expect(edit.plainText == "Dragonborn")
    }

    @Test func parsesMinimalEditTextWithoutFontOrText() throws {
        var builder = SWFEditTextBodyBuilder()
        builder.flags.useOutlines = true
        builder.variableName = ""
        let edit = try SWFEditText.parse(tag: SWFTag(code: 37, body: builder.build()))
        #expect(!edit.flags.hasText)
        #expect(!edit.flags.hasFont)
        #expect(edit.flags.useOutlines)
        #expect(edit.fontID == nil)
        #expect(edit.fontHeight == nil)
        #expect(edit.color == nil)
        #expect(edit.layout == nil)
        #expect(edit.variableName.isEmpty)
        #expect(edit.initialText == nil)
        #expect(edit.plainText == nil)
    }

    @Test func stripsHTMLMarkupForPlainText() throws {
        var builder = SWFEditTextBodyBuilder()
        builder.flags.hasText = true
        builder.flags.html = true
        builder.initialText = "<p align=\"left\"><font size=\"24\">Health</font></p>"
        let edit = try SWFEditText.parse(tag: SWFTag(code: 37, body: builder.build()))
        // Raw text is retained verbatim; plainText strips the markup.
        #expect(edit.initialText == "<p align=\"left\"><font size=\"24\">Health</font></p>")
        #expect(edit.plainText == "Health")
    }

    @Test func rejectsTruncatedEditText() {
        var builder = SWFEditTextBodyBuilder()
        builder.flags.hasFont = true
        builder.fontID = 1
        builder.fontHeight = 200
        let body = builder.build()
        #expect(throws: (any Error).self) {
            _ = try SWFEditText.parse(tag: SWFTag(code: 37, body: body.prefix(4)))
        }
    }
}
