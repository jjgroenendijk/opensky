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
        // The gamma fog colour, made linear for the sRGB target.
        let red = pow(0.2, 2.2), green = pow(0.5, 2.2)
        #expect(abs(colour.red - red) < 1e-5 && abs(colour.green - green) < 1e-5)
        #expect(abs(colour.blue - green) < 1e-5 && colour.alpha == 1)
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

    @Test func aCoverStandsOnBlackInsteadOfTheFogColour() {
        let covered = Renderer.background(fog: Self.fog, drawsSky: false, covered: true)
        #expect(covered.red == 0 && covered.green == 0 && covered.blue == 0)
    }
}
