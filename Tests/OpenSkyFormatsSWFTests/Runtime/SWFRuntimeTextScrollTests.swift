// `TextField.scroll`, `maxscroll`, and `bottomScroll` over a synthetic font, and the
// first line the scene item hands the renderer.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFRuntimeTextScrollTests {
    /// "A" and "B" with ascent 800 and descent 200: a 1000-twip line at EM 1024.
    private static func fontTag() -> SWFFixture.Tag {
        var builder = SWFFontBodyBuilder()
        builder.fontID = 1
        builder.flags.hasLayout = true
        builder.codes = [65, 66]
        builder.shapes = [
            SWFFontBodyBuilder.triangleGlyphShape(size: 700),
            SWFFontBodyBuilder.triangleGlyphShape(size: 600)
        ]
        builder.layout = SWFFontBodyBuilder.Layout(
            ascent: 800, descent: 200, leading: 0, advances: [600, 500],
            bounds: [
                SWFRect(xMin: 0, xMax: 700, yMin: -700, yMax: 0),
                SWFRect(xMin: 0, xMax: 600, yMin: -600, yMax: 0)
            ],
            kerning: []
        )
        return SWFFixture.Tag(code: 48, body: builder.build())
    }

    /// Four lines in a field two lines high.
    private static func started() throws -> (SWFMovieRuntime, SWFDisplayObject) {
        var builder = SWFEditTextBodyBuilder()
        builder.characterId = 3
        builder.bounds = SWFRect(xMin: 0, xMax: 4000, yMin: 0, yMax: 2000)
        builder.flags.hasText = true
        builder.flags.hasFont = true
        builder.flags.multiline = true
        builder.flags.wordWrap = true
        builder.fontID = 1
        builder.fontHeight = 1024
        builder.initialText = "A\nB\nA\nB"
        let runtime = try SWFRuntimeFixture.started(tags: [
            fontTag(),
            SWFFixture.Tag(code: 37, body: builder.build()),
            SWFRuntimeFixture.place(3, depth: 1, name: "field"),
            SWFDisplayFixture.showFrameTag
        ])
        return try (runtime, #require(runtime.root.child(named: "field")))
    }

    private func firstLine(_ runtime: SWFMovieRuntime) -> Int? {
        SWFRuntimeFixture.drawItems(runtime.makeScene()).first?.textFirstLine
    }

    @Test func maxscrollCountsTheLinesBelowTheField() throws {
        let (runtime, field) = try Self.started()
        #expect(runtime.member("scroll", of: field) == .number(1))
        #expect(runtime.member("maxscroll", of: field) == .number(3))
        #expect(runtime.member("bottomScroll", of: field) == .number(2))
        #expect(firstLine(runtime) == 0)
    }

    @Test func scrollMovesTheDrawnWindowAndClamps() throws {
        let (runtime, field) = try Self.started()
        #expect(runtime.setMember("scroll", of: field, to: .number(2)))
        #expect(firstLine(runtime) == 1)
        #expect(runtime.member("bottomScroll", of: field) == .number(3))
        _ = runtime.setMember("scroll", of: field, to: .number(9))
        #expect(runtime.member("scroll", of: field) == .number(3))
        #expect(runtime.member("bottomScroll", of: field) == .number(4))
    }

    /// CLIK's `ScrollBar` follows its field through `onScroller`, once per real change.
    @Test func aScrollChangeTellsTheFieldsListeners() throws {
        let (runtime, field) = try Self.started()
        let listener = runtime.runtime.makeObject()
        AS2Natives.method(runtime.runtime, on: listener, name: "onScroller") { context in
            context.thisObject?.assign(context.argument(0), for: "heard")
            return .undefined
        }
        let add = try #require(field.object.lookup("addListener")?.property.value)
        runtime.runtime.invoke(
            add,
            thisValue: .object(field.object),
            arguments: [.object(listener)]
        )
        _ = runtime.setMember("scroll", of: field, to: .number(1))
        #expect(listener.lookup("heard") == nil)
        _ = runtime.setMember("scroll", of: field, to: .number(2))
        #expect(listener.lookup("heard")?.property.value == .object(field.object))
    }

    /// GFx `textAutoSize` fits the text to the field instead, so every line is drawn.
    @Test func aSelfSizingFieldDrawsEveryLine() throws {
        let (runtime, field) = try Self.started()
        field.object.assign(.string("shrink"), for: "textAutoSize")
        #expect(runtime.member("maxscroll", of: field) == .number(1))
        #expect(firstLine(runtime) == nil)
    }
}
