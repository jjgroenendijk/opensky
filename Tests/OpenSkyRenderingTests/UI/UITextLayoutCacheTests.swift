// HUD text is shaped once per string, font, size and wrap width, and the cached
// layout draws the same quads as a fresh one.

@testable import OpenSkyRendering
import OpenSkyShaderTypes
import Testing

struct UITextLayoutCacheTests {
    private static let font = UIFont(pointSize: 14)

    private static func scene(text: String, maxWidth: Float? = 120) -> UIScene {
        let label = UILabel(text: text, font: font, color: SIMD4(1, 1, 1, 1), maxWidth: maxWidth)
        return UIScene(nodes: [UINode(anchor: .topLeft, content: .label(label))])
    }

    private static func positions(
        _ scene: UIScene, atlas: UIGlyphAtlas, scale: Float = 2
    ) -> [SIMD2<Float>] {
        scene.resolve(viewportPixels: SIMD2(800, 600), scale: scale, atlas: atlas)
            .vertices.map(\.position)
    }

    @Test func aSecondFrameShapesNothingAndDrawsTheSame() {
        let scene = Self.scene(text: "Press E to talk to the shopkeeper")
        let atlas = UIGlyphAtlas()
        let first = Self.positions(scene, atlas: atlas)
        let shaped = atlas.layouts.shapedLineCount
        let second = Self.positions(scene, atlas: atlas)

        #expect(shaped > 0)
        #expect(atlas.layouts.shapedLineCount == shaped)
        #expect(second == first)
        #expect(Self.positions(scene, atlas: UIGlyphAtlas()) == first)
    }

    @Test func newTextOrANewScaleShapesAgain() {
        let atlas = UIGlyphAtlas()
        _ = Self.positions(Self.scene(text: "Open"), atlas: atlas)
        let shaped = atlas.layouts.shapedLineCount

        _ = Self.positions(Self.scene(text: "Öffnen"), atlas: atlas)
        let afterText = atlas.layouts.shapedLineCount
        let scaled = Self.positions(Self.scene(text: "Öffnen"), atlas: atlas, scale: 3)

        #expect(afterText > shaped)
        #expect(atlas.layouts.shapedLineCount > afterText)
        let fresh = Self.positions(Self.scene(text: "Öffnen"), atlas: UIGlyphAtlas(), scale: 3)
        #expect(scaled == fresh)
    }

    @Test func cachedLayoutsMatchTheShaper() {
        let cache = UITextLayoutCache()
        let text = "A long line of HUD text that wraps at the given width"
        #expect(cache.wrap(text, font: Self.font, maxWidth: 90)
            == UITextShaper.wrap(text, font: Self.font, maxWidth: 90))
        let fresh = UITextShaper.shape(text, font: Self.font.makeCTFont(size: 28))
        let cached = cache.shape(text, font: Self.font, size: 28)
        #expect(cached.glyphs == fresh.glyphs)
        #expect(cached.width == fresh.width)
    }
}
