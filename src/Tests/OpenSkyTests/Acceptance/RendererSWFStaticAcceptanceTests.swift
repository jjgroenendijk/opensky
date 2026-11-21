// Static SWF acceptance in pixels with a synthetic menu-shaped movie. The movie
// changes the frame, a zero-alpha colour transform matches the baseline,
// `swfEnabled = false` and a cleared movie restore it byte for byte, and
// repeated frames are identical. Movies are built in code.

import Foundation
import Metal
import OpenSkyEngineTesting
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
@testable import OpenSkyRendering
import OpenSkyTagsTesting
import OpenSkyWorldFixtures
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
        let builder = SWFFontBodyBuilder.abFont(fontID: 5)
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

@Suite(.tags(.acceptance, .gpu), .unlessPlanSkips(.gpu))
struct RendererSWFStaticAcceptanceTests {
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device
    private static let canvas = OffscreenCanvas(width: 480, height: 320, shaders: .appBundle)

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func menuMovieChangesPixelsOverBaseline() throws {
        let renderer = try Self.canvas.makeRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        let withMovie = try Self.canvas.render(renderer)
        let stats = renderer.lastSWFDrawStats
        #expect(stats.drawCalls > 3, "only \(stats.drawCalls) draws encoded")
        #expect(stats.triangles > 6)
        #expect(stats.glyphs == 4, "expected 4 glyph quads, got \(stats.glyphs)")
        #expect(stats.maskDraws == 2, "expected one clip begin/end pair")
        #expect(stats.skippedItems == 0)
        let changed = OffscreenRendererFixture.changedPixels(base, withMovie)
        #expect(changed > 2000, "menu movie changed only \(changed) pixels")
    }

    /// The vanilla frame-1 pattern: content is placed and encoded but an
    /// alpha-zero CXFORM makes it contribute nothing, so the frame reproduces
    /// the movie-free baseline exactly. This is why `book.swf` and
    /// `loadingmenu.swf` come up blank without ActionScript.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func zeroAlphaColorTransformReproducesBaselineExactly() throws {
        let renderer = try Self.canvas.makeRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: true))
        let hidden = try Self.canvas.render(renderer)
        #expect(renderer.lastSWFDrawStats.drawCalls > 3, "hidden movie encoded no draws")
        #expect(hidden == base, "alpha-zero content still changed pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func disabledLayerMatchesBaselineExactly() throws {
        let renderer = try Self.canvas.makeRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        renderer.swfEnabled = false
        let disabled = try Self.canvas.render(renderer)
        #expect(disabled == base)
        #expect(renderer.lastSWFDrawStats == SWFDrawStats())
        renderer.swfEnabled = true
        let reEnabled = try Self.canvas.render(renderer)
        #expect(
            OffscreenRendererFixture.changedPixels(base, reEnabled) > 2000,
            "re-enabling drew nothing"
        )
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func clearedMovieMatchesBaselineExactly() throws {
        let renderer = try Self.canvas.makeRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        _ = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(nil)
        let cleared = try Self.canvas.render(renderer)
        #expect(cleared == base)
        #expect(renderer.swfScene == nil)
        #expect(renderer.lastSWFDrawStats == SWFDrawStats())
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func repeatedFramesAreByteIdentical() throws {
        let renderer = try Self.canvas.makeRenderer()
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        // Warm the glyph atlas so no upload happens between the compared frames.
        _ = try Self.canvas.render(renderer)
        let first = try Self.canvas.render(renderer)
        let second = try Self.canvas.render(renderer)
        #expect(first == second)
    }

    /// A movie colour is a gamma value: an opaque grey of 128 reads back as 128 from the
    /// sRGB target, not as the brighter value a linear write would give.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func anOpaqueColourReadsBackAsAuthored() throws {
        let grey = SWFColor(red: 128, green: 128, blue: 128, alpha: 255)
        var place = SWFDisplayFixture.Place2()
        place.depth = 1
        place.characterId = 1
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 1, width: 60000, height: 60000, color: grey
            ),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.showFrameTag
        ])
        let renderer = try Self.canvas.makeRenderer()
        try renderer.setSWFMovie(SWFMovieScene(movie: movie))
        let pixels = try Self.canvas.render(renderer)
        let offset = (Self.canvas.height / 2 * Self.canvas.width + Self.canvas.width / 2) * 4
        for channel in 0 ..< 3 {
            #expect(abs(Int(pixels[offset + channel]) - 128) <= 2, "channel \(channel)")
        }
    }

    /// A morph placed at the middle ratio fills the middle form: a point inside it
    /// but outside the start form changes, and a point past it does not.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aMorphDrawsItsMiddleForm() throws {
        func render(ratio: UInt16) throws -> [UInt8] {
            let movie = try SWFDisplayFixture.movie(tags: [
                SWFMorphShapeFixture.tag(characterId: 1, scale: 20),
                SWFDisplayFixture.placeObject2Tag(.init(depth: 1, characterId: 1, ratio: ratio)),
                SWFDisplayFixture.showFrameTag
            ])
            let renderer = try Self.canvas.makeRenderer()
            try renderer.setSWFMovie(SWFMovieScene(movie: movie))
            return try Self.canvas.render(renderer)
        }
        // The 8000 by 6000 twip stage fits the canvas height and is centred.
        let scale = Double(Self.canvas.height) / 6000
        let left = (Double(Self.canvas.width) - 8000 * scale) / 2
        func pixel(_ pixels: [UInt8], x: Double, y: Double) -> [UInt8] {
            let offset = (Int(y * scale) * Self.canvas.width + Int(left + x * scale)) * 4
            return Array(pixels[offset ..< offset + 3])
        }
        let start = try render(ratio: 0)
        let middle = try render(ratio: 0x8000)
        #expect(pixel(middle, x: 3000, y: 1500) != pixel(start, x: 3000, y: 1500))
        #expect(pixel(middle, x: 5000, y: 1500) == pixel(start, x: 5000, y: 1500))
    }

    /// Flash blends gamma values: black at 60% alpha over grey 128 reads back
    /// 0.4 x 128, about 51. A blend of linear values gave about 82.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aTranslucentPartBlendsInGamma() throws {
        let grey = SWFColor(red: 128, green: 128, blue: 128, alpha: 255)
        let black = SWFColor(red: 0, green: 0, blue: 0, alpha: 255)
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 1, width: 60000, height: 60000, color: grey
            ),
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 2, width: 60000, height: 60000, color: black
            ),
            SWFDisplayFixture.placeObject2Tag(.init(depth: 1, characterId: 1)),
            SWFDisplayFixture.placeObject2Tag(.init(
                depth: 2, characterId: 2,
                cxform: .init(multiplyTerms: [256, 256, 256, 154])
            )),
            SWFDisplayFixture.showFrameTag
        ])
        let renderer = try Self.canvas.makeRenderer()
        try renderer.setSWFMovie(SWFMovieScene(movie: movie))
        let pixels = try Self.canvas.render(renderer)
        let offset = (Self.canvas.height / 2 * Self.canvas.width + Self.canvas.width / 2) * 4
        for channel in 0 ..< 3 {
            #expect(abs(Int(pixels[offset + channel]) - 51) <= 3, "channel \(channel)")
        }
    }

    /// Reassigning the same movie must land on the same frame: the acceptance
    /// path in the app swaps movies repeatedly through the picker.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func reassigningTheMovieReproducesItsFrame() throws {
        let renderer = try Self.canvas.makeRenderer()
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        _ = try Self.canvas.render(renderer)
        let first = try Self.canvas.render(renderer)
        let firstStats = renderer.lastSWFDrawStats
        try renderer.setSWFMovie(nil)
        _ = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(SWFMenuFixture.scene(hidden: false))
        let second = try Self.canvas.render(renderer)
        #expect(first == second)
        #expect(renderer.lastSWFDrawStats == firstStats)
    }
}
