// An HTML field before any script sets it: `htmlText` reads back the authored HTML, and a
// `<font face>` name finds the movie's own font.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFRuntimeHTMLFieldTests {
    private static let html = "<p align='center'><font face='TestFont' size='20'>AB</font></p>"

    private static func started() throws -> (SWFMovieRuntime, SWFDisplayObject) {
        var builder = SWFEditTextBodyBuilder()
        builder.characterId = 3
        builder.flags.hasText = true
        builder.flags.hasFont = true
        builder.flags.html = true
        builder.fontID = 1
        builder.fontHeight = 400
        builder.initialText = html
        let font = SWFFontBodyBuilder.abFont(fontID: 1)
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFFixture.Tag(code: 48, body: font.build()),
            SWFFixture.Tag(code: 37, body: builder.build()),
            SWFRuntimeFixture.place(3, depth: 1, name: "field"),
            SWFDisplayFixture.showFrameTag
        ])
        return try (runtime, #require(runtime.root.child(named: "field")))
    }

    @Test func htmlTextReadsTheAuthoredHTMLUntilAScriptSetsText() throws {
        let (runtime, field) = try Self.started()
        #expect(runtime.member("htmlText", of: field) == .string(Self.html))
        #expect(runtime.setMember("text", of: field, to: .string("B")))
        #expect(runtime.member("htmlText", of: field) == .string("B"))
    }

    @Test func aFontFaceNameFindsTheMoviesOwnFont() throws {
        let (runtime, _) = try Self.started()
        #expect(runtime.movieScene.font(named: "TestFont")?.fontID == 1)
        #expect(runtime.movieScene.font(named: "Missing") == nil)
    }
}
