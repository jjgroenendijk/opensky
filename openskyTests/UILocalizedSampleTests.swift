// Deterministic layout coverage for the UI Lab localized-strings preview
// (M8.1.4). The sample scene resolves every visible string through
// LocalizedLabels.label(for:) over invented in-code fixtures: known keys
// resolve, the deliberately unknown key stays verbatim (the vanilla-observable
// fallback), the long-string case wraps at its point width, the clip case runs
// past the frame edge, and resolve stays byte-deterministic. No Metal device.

@testable import opensky
import simd
import Testing

struct UILocalizedSampleTests {
    private static let viewport = SIMD2<Float>(480, 320)

    /// Label texts of the built-in localized sample scene, in node order.
    private var sampleTexts: [String] {
        UIScene.localizedSample.nodes.compactMap { node in
            if case let .label(label) = node.content {
                return label.text
            }
            return nil
        }
    }

    @Test
    func sampleProviderResolvesInventedKeys() {
        let labels = LocalizedLabels.uiLabSample
        #expect(labels.keyCount == 4)
        #expect(labels.fileCount == 1)
        #expect(labels.language == "english")
        #expect(labels.label(for: "$OPENSKY_UILAB_TITLE") == "Localized strings")
    }

    @Test
    func unknownKeyFallsBackVerbatim() {
        let labels = LocalizedLabels.uiLabSample
        let missing = UIScene.localizedSampleMissingToken
        #expect(labels.value(forKey: missing) == nil)
        #expect(labels.label(for: missing) == missing)
    }

    @Test
    func sceneShowsResolvedTextAndVerbatimFallback() {
        let texts = sampleTexts
        // Every known key resolved: no $ tokens remain except the deliberate one.
        #expect(texts.contains("Localized strings"))
        #expect(texts.filter { $0.hasPrefix("$") } == [UIScene.localizedSampleMissingToken])
    }

    @Test
    func longStringCaseWrapsAtItsPointWidth() throws {
        let scene = UIScene.localizedSample
        let long = try #require(
            scene.nodes.compactMap { node -> UILabel? in
                if case let .label(label) = node.content, label.maxWidth != nil {
                    return label
                }
                return nil
            }.first
        )
        #expect(long.maxWidth == UIScene.localizedSampleWrapWidth)
        let lines = UITextShaper.wrap(
            long.text, font: long.font, maxWidth: UIScene.localizedSampleWrapWidth
        )
        #expect(lines.count > 1, "long-string case did not wrap: \(lines)")
    }

    @Test
    func clipCaseRunsPastTheFrameEdge() {
        let list = UIScene.localizedSample.resolve(
            viewportPixels: Self.viewport, scale: 1, atlas: UIGlyphAtlas()
        )
        let maxX = list.vertices.map(\.position.x).max() ?? 0
        #expect(
            maxX > Self.viewport.x,
            "clip case ends at \(maxX), inside the \(Self.viewport.x)px frame"
        )
    }

    @Test
    func resolveIsDeterministicAcrossScales() {
        for scale: Float in [1, 2] {
            let atlas = UIGlyphAtlas()
            let first = UIScene.localizedSample.resolve(
                viewportPixels: Self.viewport, scale: scale, atlas: atlas
            )
            let second = UIScene.localizedSample.resolve(
                viewportPixels: Self.viewport, scale: scale, atlas: atlas
            )
            #expect(first.quadCount == second.quadCount)
            #expect(vertexBytes(first.vertices) == vertexBytes(second.vertices))
            #expect(first.quadCount > 20)
            #expect(first.glyphCount > 10)
        }
    }

    private func vertexBytes(_ vertices: [UIVertex]) -> [UInt8] {
        vertices.withUnsafeBytes { Array($0) }
    }
}
