import Metal
@testable import OpenSkyRendering
import simd
import Testing

@MainActor
struct RendererBackgroundTests {
    private static let fog = Renderer.FrameFog(
        nearColor: [0.1, 0.1, 0.1], farColor: [0.2, 0.5, 0.5],
        distances: [0, 1000, 1, 1], enabled: 1
    )

    @Test func aSkylessSceneShowsTheFarFogColourInItsGaps() {
        let colour = Renderer.background(fog: Self.fog, drawsSky: false)
        #expect(abs(colour.red - 0.2) < 1e-6 && abs(colour.green - 0.5) < 1e-6)
        #expect(abs(colour.blue - 0.5) < 1e-6 && colour.alpha == 1)
    }

    @Test func aSkyOrNoFogKeepsTheBlackClear() {
        let sky = Renderer.background(fog: Self.fog, drawsSky: true)
        #expect(sky.red == 0 && sky.green == 0 && sky.blue == 0)
        let noFog = Renderer.FrameFog(
            nearColor: .zero, farColor: [1, 1, 1], distances: [0, 1, 1, 0], enabled: 0
        )
        let black = Renderer.background(fog: noFog, drawsSky: false)
        #expect(black.red == 0 && black.green == 0 && black.blue == 0)
    }
}
