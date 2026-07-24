// Metal-gated offscreen tests for the SWF display-list layer (milestone
// 8.2.4): a synthetic in-code movie (colored rectangles at depths, a clip
// layer, an edit text over a synthetic font) rendered over the demo scene.
// The overlay must change pixels, an off toggle must reproduce the no-movie
// baseline exactly, repeated frames must be byte-identical (determinism), a
// clip layer must reduce the covered area, and the draw stats must count
// draws/triangles/glyphs/masks. Pattern from RendererUITests.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RendererSWFTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    private static let width = 480
    private static let height = 320
    /// Fixed animation time: the 3D demo scene is identical across renders,
    /// so any pixel delta comes only from the SWF layer.
    private static let animationTime: Float = 1

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
        var fontBuilder = SWFFontBodyBuilder()
        fontBuilder.fontID = 1
        fontBuilder.flags.hasLayout = true
        fontBuilder.codes = [65, 66]
        fontBuilder.shapes = [
            SWFFontBodyBuilder.triangleGlyphShape(size: 700),
            SWFFontBodyBuilder.triangleGlyphShape(size: 600)
        ]
        fontBuilder.layout = SWFFontBodyBuilder.Layout(
            ascent: 800,
            descent: 200,
            leading: 0,
            advances: [600, 500],
            bounds: [
                SWFRect(xMin: 0, xMax: 700, yMin: -700, yMax: 0),
                SWFRect(xMin: 0, xMax: 600, yMin: -600, yMax: 0)
            ]
        )
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
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(Self.twoRectMovie())
        let withMovie = try Self.render(renderer)
        let changed = Self.changedPixels(base, withMovie)
        #expect(changed > 2000, "SWF layer changed only \(changed) pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func disabledLayerMatchesNoMovieBaselineExactly() throws {
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(Self.twoRectMovie())
        renderer.swfEnabled = false
        let disabled = try Self.render(renderer)
        #expect(disabled == base)
        #expect(renderer.lastSWFDrawStats == SWFDrawStats())
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func repeatedRenderIsByteIdentical() throws {
        let renderer = try Self.makeRenderer()
        try renderer.setSWFMovie(Self.twoRectMovie())
        // Warm the glyph atlas/pipelines, then compare two settled frames.
        _ = try Self.render(renderer)
        let first = try Self.render(renderer)
        let second = try Self.render(renderer)
        #expect(first == second)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func clipLayerRestrictsCoverage() throws {
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(Self.clipMovie(clipped: false))
        let unclipped = try Self.render(renderer)
        try renderer.setSWFMovie(Self.clipMovie(clipped: true))
        let clipped = try Self.render(renderer)
        #expect(renderer.lastSWFDrawStats.maskDraws == 2)
        let unclippedChanged = Self.changedPixels(base, unclipped)
        let clippedChanged = Self.changedPixels(base, clipped)
        #expect(clippedChanged > 100, "clipped content vanished entirely")
        #expect(
            clippedChanged < unclippedChanged / 4,
            "clip did not restrict coverage: \(clippedChanged) vs \(unclippedChanged)"
        )
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func statsCountDrawsAndTriangles() throws {
        let renderer = try Self.makeRenderer()
        try renderer.setSWFMovie(Self.twoRectMovie())
        _ = try Self.render(renderer)
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
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(Self.textMovie())
        let withText = try Self.render(renderer)
        let stats = renderer.lastSWFDrawStats
        #expect(stats.glyphs == 2)
        #expect(stats.drawCalls == 1)
        let changed = Self.changedPixels(base, withText)
        #expect(changed > 100, "text changed only \(changed) pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func clearingTheMovieRestoresBaseline() throws {
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(Self.twoRectMovie())
        _ = try Self.render(renderer)
        try renderer.setSWFMovie(nil)
        let cleared = try Self.render(renderer)
        #expect(cleared == base)
        #expect(renderer.swfScene == nil)
    }

    // MARK: - Helpers

    @MainActor
    private static func makeRenderer() throws -> Renderer {
        let device = try #require(self.device)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view)
    }

    @MainActor
    private static func render(_ renderer: Renderer) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(
            width: width, height: height, animationTime: animationTime
        )
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return } // non-empty
            texture.getBytes(
                base,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        return pixels
    }

    /// Count of pixels differing beyond a small per-channel threshold.
    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        var changed = 0
        for pixel in stride(from: 0, to: lhs.count, by: 4) {
            let delta = (0 ..< 3).map { abs(Int(lhs[pixel + $0]) - Int(rhs[pixel + $0])) }
                .max() ?? 0
            if delta > 8 {
                changed += 1
            }
        }
        return changed
    }
}
