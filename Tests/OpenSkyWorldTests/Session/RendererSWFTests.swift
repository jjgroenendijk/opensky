// Offscreen tests for the SWF display-list layer with a synthetic movie over
// the demo scene: pixels change, an off toggle matches the baseline, frames
// repeat byte for byte, a clip layer shrinks the covered area, and the draw
// stats count draws, triangles, glyphs, and masks.

import FormatsSWFTesting
import Foundation
import Metal
@testable import OpenSkyFormatsSWF
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import RenderingTesting
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct RendererSWFTests {
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device
    private static let canvas = OffscreenCanvas(width: 480, height: 320, shaders: .packageFixture)

    private static let red = SWFColor(red: 255, green: 0, blue: 0, alpha: 255)
    private static let blue = SWFColor(red: 0, green: 0, blue: 255, alpha: 255)

    // MARK: - Synthetic movies

    /// Red 200x200 px rectangle at (50, 50) px, blue 100x100 px at (200, 100).
    private static func twoRectMovie() throws -> SWFMovieScene {
        var placeRed = SWFDisplayFixture.Place2()
        placeRed.depth = 1
        placeRed.characterId = 1
        placeRed.matrix = SWFDisplayFixture.MatrixSpec(translateX: 1000, translateY: 1000)
        var placeBlue = SWFDisplayFixture.Place2()
        placeBlue.depth = 2
        placeBlue.characterId = 2
        placeBlue.matrix = SWFDisplayFixture.MatrixSpec(translateX: 4000, translateY: 2000)
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 1, width: 4000, height: 4000, color: red
            ),
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 2, width: 2000, height: 2000, color: blue
            ),
            SWFDisplayFixture.placeObject2Tag(placeRed),
            SWFDisplayFixture.placeObject2Tag(placeBlue),
            SWFDisplayFixture.showFrameTag
        ])
        return SWFMovieScene(movie: movie)
    }

    /// A large red rectangle, optionally clipped by a small mask layer.
    private static func clipMovie(clipped: Bool) throws -> SWFMovieScene {
        var tags: [SWFFixture.Tag] = [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 1, width: 6000, height: 5000, color: red
            ),
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 2, width: 1500, height: 1500, color: blue
            )
        ]
        if clipped {
            var mask = SWFDisplayFixture.Place2()
            mask.depth = 1
            mask.characterId = 2
            mask.clipDepth = 2
            mask.matrix = SWFDisplayFixture.MatrixSpec(translateX: 2000, translateY: 2000)
            tags.append(SWFDisplayFixture.placeObject2Tag(mask))
        }
        var content = SWFDisplayFixture.Place2()
        content.depth = 2
        content.characterId = 1
        content.matrix = SWFDisplayFixture.MatrixSpec(translateX: 500, translateY: 500)
        tags.append(SWFDisplayFixture.placeObject2Tag(content))
        tags.append(SWFDisplayFixture.showFrameTag)
        return try SWFMovieScene(movie: SWFDisplayFixture.movie(tags: tags))
    }

    /// An edit text ("AB") over a synthetic two-glyph font.
    private static func textMovie() throws -> SWFMovieScene {
        let fontBuilder = SWFFontBodyBuilder.abFont(fontID: 1)
        var editBuilder = SWFEditTextBodyBuilder()
        editBuilder.characterId = 2
        editBuilder.bounds = SWFRect(xMin: 0, xMax: 6000, yMin: 0, yMax: 3000)
        editBuilder.flags.hasText = true
        editBuilder.flags.hasFont = true
        editBuilder.flags.hasTextColor = true
        editBuilder.fontID = 1
        editBuilder.fontHeight = 2000
        editBuilder.color = SWFColor(red: 255, green: 255, blue: 0, alpha: 255)
        editBuilder.initialText = "AB"
        var place = SWFDisplayFixture.Place2()
        place.depth = 1
        place.characterId = 2
        place.matrix = SWFDisplayFixture.MatrixSpec(translateX: 500, translateY: 500)
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFFixture.Tag(code: 48, body: fontBuilder.build()),
            SWFFixture.Tag(code: 37, body: editBuilder.build()),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.showFrameTag
        ])
        return SWFMovieScene(movie: movie)
    }

    // MARK: - Tests

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func movieChangesPixelsOverBaseline() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(Self.twoRectMovie())
        let withMovie = try Self.canvas.render(renderer)
        let changed = OffscreenRendererFixture.changedPixels(base, withMovie)
        #expect(changed > 2000, "SWF layer changed only \(changed) pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func disabledLayerMatchesNoMovieBaselineExactly() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(Self.twoRectMovie())
        renderer.swfEnabled = false
        let disabled = try Self.canvas.render(renderer)
        #expect(disabled == base)
        #expect(renderer.lastSWFDrawStats == SWFDrawStats())
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func repeatedRenderIsByteIdentical() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        try renderer.setSWFMovie(Self.twoRectMovie())
        // Warm the glyph atlas/pipelines, then compare two settled frames.
        _ = try Self.canvas.render(renderer)
        let first = try Self.canvas.render(renderer)
        let second = try Self.canvas.render(renderer)
        #expect(first == second)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func clipLayerRestrictsCoverage() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(Self.clipMovie(clipped: false))
        let unclipped = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(Self.clipMovie(clipped: true))
        let clipped = try Self.canvas.render(renderer)
        #expect(renderer.lastSWFDrawStats.maskDraws == 2)
        let unclippedChanged = OffscreenRendererFixture.changedPixels(base, unclipped)
        let clippedChanged = OffscreenRendererFixture.changedPixels(base, clipped)
        #expect(clippedChanged > 100, "clipped content vanished entirely")
        #expect(
            clippedChanged < unclippedChanged / 4,
            "clip did not restrict coverage: \(clippedChanged) vs \(unclippedChanged)"
        )
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func statsCountDrawsAndTriangles() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        try renderer.setSWFMovie(Self.twoRectMovie())
        _ = try Self.canvas.render(renderer)
        let stats = renderer.lastSWFDrawStats
        #expect(stats.drawCalls == 2)
        #expect(stats.triangles == 4)
        #expect(stats.glyphs == 0)
        #expect(stats.maskDraws == 0)
        #expect(stats.skippedItems == 0)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func editTextDrawsGlyphsThroughTheAtlas() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(Self.textMovie())
        let withText = try Self.canvas.render(renderer)
        let stats = renderer.lastSWFDrawStats
        #expect(stats.glyphs == 2)
        #expect(stats.drawCalls == 1)
        let changed = OffscreenRendererFixture.changedPixels(base, withText)
        #expect(changed > 100, "text changed only \(changed) pixels")
    }

    /// The glyph atlas is shared and fixed-size, so a movie swap must return
    /// the old cells, or the atlas fills and later text draws nothing.
    @Test(.enabled(if: Self.hasMetal4Device), .tags(.slow))
    @MainActor
    func swappingMoviesReleasesTheirGlyphCells() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        try renderer.setSWFMovie(Self.textMovie())
        _ = try Self.canvas.render(renderer)
        let firstOccupancy = renderer.lastUIDrawStats.atlasGlyphs
        for _ in 0 ..< 40 {
            try renderer.setSWFMovie(Self.textMovie())
            _ = try Self.canvas.render(renderer)
        }
        #expect(renderer.lastSWFDrawStats.glyphs == 2)
        #expect(renderer.lastUIDrawStats.atlasGlyphs == firstOccupancy)
        #expect(renderer.lastUIDrawStats.atlasPackFailures == 0)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func clearingTheMovieRestoresBaseline() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(Self.twoRectMovie())
        _ = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(nil)
        let cleared = try Self.canvas.render(renderer)
        #expect(cleared == base)
        #expect(renderer.swfScene == nil)
    }
}
