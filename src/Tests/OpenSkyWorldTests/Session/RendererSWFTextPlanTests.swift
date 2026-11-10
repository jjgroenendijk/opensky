// The SWF text planner without a GPU: static and edit texts become glyph runs with
// atlas keys in the movie's generation, and a text with no usable font is counted
// as skipped. Synthetic movies built with the SWF fixtures.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
@testable import OpenSkyRendering
import Testing

struct RendererSWFTextPlanTests {
    private static let yellow = SWFColor(red: 255, green: 255, blue: 0, alpha: 255)

    /// Font 1 with glyphs "A" and "B"; edit text 2 and static text 3 in font 1;
    /// static text 4 in font 9, which the movie does not define.
    private static func movie() throws -> SWFMovie {
        var edit = SWFEditTextBodyBuilder()
        edit.characterId = 2
        edit.flags.hasText = true
        edit.flags.hasFont = true
        edit.flags.hasTextColor = true
        edit.fontID = 1
        edit.fontHeight = 2000
        edit.color = yellow
        edit.initialText = "AB"
        let glyphs = [
            SWFTextBodyBuilder.Glyph(index: 0, advance: 200),
            SWFTextBodyBuilder.Glyph(index: 1, advance: 180)
        ]
        var known = SWFTextBodyBuilder()
        known.characterId = 3
        known.records = [SWFTextBodyBuilder.Record(
            fontID: 1, textHeight: 240, color: yellow, glyphs: glyphs
        )]
        var unknown = SWFTextBodyBuilder()
        unknown.characterId = 4
        unknown.records = [SWFTextBodyBuilder.Record(
            fontID: 9, textHeight: 240, color: yellow, glyphs: glyphs
        )]
        var tags = [
            SWFFixture.Tag(code: 48, body: SWFFontBodyBuilder.abFont(fontID: 1).build()),
            SWFFixture.Tag(code: 37, body: edit.build()),
            SWFFixture.Tag(code: 11, body: known.build()),
            SWFFixture.Tag(code: 11, body: unknown.build())
        ]
        for character: UInt16 in 2 ... 4 {
            var place = SWFDisplayFixture.Place2()
            place.depth = character
            place.characterId = character
            tags.append(SWFDisplayFixture.placeObject2Tag(place))
        }
        tags.append(SWFDisplayFixture.showFrameTag)
        return try SWFDisplayFixture.movie(tags: tags)
    }

    @Test func plansEachTextInTheMovieGeneration() throws {
        let movie = try Self.movie()
        let planner = SWFMovieResources.TextPlanner(
            scene: SWFMovieScene(movie: movie), generation: 3
        )
        let plans = planner.plan(commands: SWFScene.build(movie: movie).commands)
        let runs = plans.keys.sorted().compactMap { plans[$0] }
        try #require(runs.count == 3)
        let fontKey = (3 << SWFMovieResources.TextPlanner.generationShift) | 1
        #expect(runs[0].map(\.fontKey) == [fontKey])
        #expect(runs[0].first?.color == SIMD4<Float>(1, 1, 0, 1))
        #expect(runs[0].first?.glyphs.count == 2)
        #expect(runs[1].map(\.fontKey) == [fontKey])
        #expect(runs[1].first?.glyphs.count == 2)
        #expect(runs[2].isEmpty)
        #expect(planner.skipped == 1)
        #expect(SWFMovieResources.TextPlanner.generation(forFontKey: fontKey) == 3)
    }
}
