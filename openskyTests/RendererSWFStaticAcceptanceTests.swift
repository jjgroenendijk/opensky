// Metal-gated pixel evidence for the M8.2.5 static-render acceptance (todo
// 8.2.5). The fixture is a synthetic menu-shaped movie built in code — a
// background plate, a nested sprite, a clip layer, and an edit text over a
// synthetic font — never an extracted game file (AGENTS.md "Legal & IP
// boundary"). Vanilla-install figures are gathered with `openskycli swf
// render-sweep` and quoted in docs/formats/swf.md, not committed here.
//
// The acceptance points: the movie changes the frame over a movie-free
// baseline, a zero-alpha CXFORM reproduces that baseline exactly (the reason
// most vanilla menus render blank at frame 1 until ActionScript runs),
// `swfEnabled = false` and a cleared movie both restore the baseline byte for
// byte, and repeated frames are byte-identical.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

/// Synthetic menu movie: plate + sprite + clip layer + edit text. `hidden`
/// applies the vanilla frame-1 pattern — an alpha-zero CXFORM on every
/// top-level placement.
private enum SWFMenuFixture {
    static let plate = SWFColor(red: 40, green: 40, blue: 60, alpha: 255)
    static let panel = SWFColor(red: 220, green: 180, blue: 90, alpha: 255)
    static let accent = SWFColor(red: 30, green: 200, blue: 120, alpha: 255)
    static let ink = SWFColor(red: 255, green: 255, blue: 255, alpha: 255)

    /// CXFORM multiplying alpha by zero (terms are 8.8 fixed, 256 == 1.0).
    private static var alphaZero: SWFDisplayFixture.CxformSpec {
        SWFDisplayFixture.CxformSpec(multiplyTerms: [256, 256, 256, 0], addTerms: nil, nbits: 12)
    }

    static func scene(hidden: Bool) throws -> SWFMovieScene {
        try SWFMovieScene(movie: SWFDisplayFixture.movie(tags: definitions() + placements(hidden)))
    }

    private static func definitions() -> [SWFFixture.Tag] {
        [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 1, width: 7000, height: 5000, color: plate
            ),
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 2, width: 2000, height: 1200, color: panel
            ),
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 3, width: 1600, height: 900, color: accent
            ),
            spriteTag(),
            fontTag(),
            editTextTag()
        ]
    }

    /// Two panels inside one sprite, so the flattener concatenates the sprite's
    /// placement with each child's.
    private static func spriteTag() -> SWFFixture.Tag {
        var first = SWFDisplayFixture.Place2()
        first.depth = 1
        first.characterId = 2
        var second = SWFDisplayFixture.Place2()
        second.depth = 2
        second.characterId = 2
        second.matrix = SWFDisplayFixture.MatrixSpec(translateX: 0, translateY: 1600)
        return SWFDisplayFixture.spriteTag(characterId: 4, frameCount: 1, tags: [
            SWFDisplayFixture.placeObject2Tag(first),
            SWFDisplayFixture.placeObject2Tag(second),
            SWFDisplayFixture.showFrameTag
        ])
    }

    private static func fontTag() -> SWFFixture.Tag {
        var builder = SWFFontBodyBuilder()
        builder.fontID = 5
        builder.flags.hasLayout = true
        builder.codes = [65, 66]
        builder.shapes = [
            SWFFontBodyBuilder.triangleGlyphShape(size: 700),
            SWFFontBodyBuilder.triangleGlyphShape(size: 600)
        ]
        builder.layout = SWFFontBodyBuilder.Layout(
            ascent: 800,
            descent: 200,
            leading: 0,
            advances: [600, 500],
            bounds: [
                SWFRect(xMin: 0, xMax: 700, yMin: -700, yMax: 0),
                SWFRect(xMin: 0, xMax: 600, yMin: -600, yMax: 0)
            ]
        )
        return SWFFixture.Tag(code: 48, body: builder.build())
    }

    private static func editTextTag() -> SWFFixture.Tag {
        var builder = SWFEditTextBodyBuilder()
        builder.characterId = 6
        builder.bounds = SWFRect(xMin: 0, xMax: 6000, yMin: 0, yMax: 3000)
        builder.flags.hasText = true
        builder.flags.hasFont = true
        builder.flags.hasTextColor = true
        builder.fontID = 5
        builder.fontHeight = 1600
        builder.color = ink
        builder.initialText = "ABBA"
        return SWFFixture.Tag(code: 37, body: builder.build())
    }

    /// Depth order: plate, clip mask (through depth 4), sprite, text.
    private static func placements(_ hidden: Bool) -> [SWFFixture.Tag] {
        let cxform = hidden ? alphaZero : nil
        var plate = SWFDisplayFixture.Place2()
        plate.depth = 1
        plate.characterId = 1
        plate.matrix = SWFDisplayFixture.MatrixSpec(translateX: 500, translateY: 500)
        plate.cxform = cxform
        var mask = SWFDisplayFixture.Place2()
        mask.depth = 2
        mask.characterId = 3
        mask.clipDepth = 3
        mask.matrix = SWFDisplayFixture.MatrixSpec(translateX: 1200, translateY: 1200)
        var sprite = SWFDisplayFixture.Place2()
        sprite.depth = 3
        sprite.characterId = 4
        sprite.matrix = SWFDisplayFixture.MatrixSpec(translateX: 900, translateY: 900)
        sprite.cxform = cxform
        var text = SWFDisplayFixture.Place2()
        text.depth = 4
        text.characterId = 6
        text.matrix = SWFDisplayFixture.MatrixSpec(translateX: 800, translateY: 4200)
        text.cxform = cxform
        return [plate, mask, sprite, text]
            .map(SWFDisplayFixture.placeObject2Tag)
            + [SWFDisplayFixture.showFrameTag]
    }
}

struct RendererSWFStaticAcceptanceTests {
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
    /// Fixed animation time: the demo scene is identical across renders, so any
    /// pixel delta comes only from the SWF layer.
    private static let animationTime: Float = 1

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func menuMovieChangesPixelsOverBaseline() throws {
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        let withMovie = try Self.render(renderer)
        let stats = renderer.lastSWFDrawStats
        #expect(stats.drawCalls > 3, "only \(stats.drawCalls) draws encoded")
        #expect(stats.triangles > 6)
        #expect(stats.glyphs == 4, "expected 4 glyph quads, got \(stats.glyphs)")
        #expect(stats.maskDraws == 2, "expected one clip begin/end pair")
        #expect(stats.skippedItems == 0)
        let changed = Self.changedPixels(base, withMovie)
        #expect(changed > 2000, "menu movie changed only \(changed) pixels")
    }

    /// The vanilla frame-1 pattern: content is placed and encoded but an
    /// alpha-zero CXFORM makes it contribute nothing, so the frame reproduces
    /// the movie-free baseline exactly. This is why `book.swf` and
    /// `loadingmenu.swf` come up blank without ActionScript.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func zeroAlphaColorTransformReproducesBaselineExactly() throws {
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: true))
        let hidden = try Self.render(renderer)
        #expect(renderer.lastSWFDrawStats.drawCalls > 3, "hidden movie encoded no draws")
        #expect(hidden == base, "alpha-zero content still changed pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func disabledLayerMatchesBaselineExactly() throws {
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        renderer.swfEnabled = false
        let disabled = try Self.render(renderer)
        #expect(disabled == base)
        #expect(renderer.lastSWFDrawStats == SWFDrawStats())
        renderer.swfEnabled = true
        let reEnabled = try Self.render(renderer)
        #expect(Self.changedPixels(base, reEnabled) > 2000, "re-enabling drew nothing")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func clearedMovieMatchesBaselineExactly() throws {
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        _ = try Self.render(renderer)
        try renderer.setSWFMovie(nil)
        let cleared = try Self.render(renderer)
        #expect(cleared == base)
        #expect(renderer.swfScene == nil)
        #expect(renderer.lastSWFDrawStats == SWFDrawStats())
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func repeatedFramesAreByteIdentical() throws {
        let renderer = try Self.makeRenderer()
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        // Warm the glyph atlas so no upload happens between the compared frames.
        _ = try Self.render(renderer)
        let first = try Self.render(renderer)
        let second = try Self.render(renderer)
        #expect(first == second)
    }

    /// Reassigning the same movie must land on the same frame: the acceptance
    /// path in the app swaps movies repeatedly through the picker.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func reassigningTheMovieReproducesItsFrame() throws {
        let renderer = try Self.makeRenderer()
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        _ = try Self.render(renderer)
        let first = try Self.render(renderer)
        let firstStats = renderer.lastSWFDrawStats
        try renderer.setSWFMovie(nil)
        _ = try Self.render(renderer)
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        let second = try Self.render(renderer)
        #expect(first == second)
        #expect(renderer.lastSWFDrawStats == firstStats)
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
