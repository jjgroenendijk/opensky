// The screen blood quads: clip-space corners, the aspect correction, and the
// order that lets one draw take every splatter and the next every flare.

@testable import OpenSkyRendering
import OpenSkyShaderTypes
import simd
import Testing

struct ScreenBloodLayerTests {
    @Test
    func splattersComeBeforeFlaresAndEachIsSixVertices() {
        let splats = [
            ScreenBloodSplat(
                center: SIMD2(0.5, 0.5), size: 0.1, rotation: 0, opacity: 1, layer: .flare
            ),
            ScreenBloodSplat(
                center: SIMD2(0.5, 0.5), size: 0.2, rotation: 0, opacity: 0.5, layer: .splatter
            )
        ]
        let vertices = ScreenBloodLayer.vertices(splats, aspect: 2)
        #expect(vertices.count == 12)
        #expect(vertices[0].color.w == 0.5, "the splatter first")
        #expect(vertices[6].color.w == 1)
    }

    @Test
    func aQuadIsCentredAndKeepsItsShapeOnAWideScreen() {
        let splat = ScreenBloodSplat(
            center: SIMD2(0.75, 0.25), size: 0.2, rotation: 0, opacity: 1, layer: .splatter
        )
        let vertices = ScreenBloodLayer.vertices([splat], aspect: 2)
        let xs = vertices.map(\.position.x)
        let ys = vertices.map(\.position.y)
        #expect(abs((xs.min() ?? 0) - 0.4) < 1e-5)
        #expect(abs((xs.max() ?? 0) - 0.6) < 1e-5)
        #expect(abs((ys.min() ?? 0) - 0.3) < 1e-5)
        #expect(abs((ys.max() ?? 0) - 0.7) < 1e-5)
    }
}
