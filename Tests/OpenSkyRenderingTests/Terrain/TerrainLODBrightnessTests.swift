// The terrain LOD curve: a texture the Creation Kit brightened, darkened as the
// landscape noise shader does, gives back the source brightness.

@testable import OpenSkyRendering
import Testing

struct TerrainLODBrightnessTests {
    @Test(arguments: [Float(0.05), 0.12, 0.2, 0.3, 0.4])
    func darkeningUndoesBrightening(source: Float) {
        let curve = TerrainLODBrightness.vanilla
        let round = curve.darkened(curve.brightened(source))
        #expect(abs(round - source) < 0.0005)
    }

    @Test func vanillaCurveMatchesMeasuredGain() {
        // Typical baked land is 0.12 to 0.37 in gamma; the measured mean gain is 1.93.
        let curve = TerrainLODBrightness.vanilla
        let ratios = [Float(0.12), 0.2, 0.3].map { curve.brightened($0) / $0 }
        #expect(ratios.allSatisfy { (1.7 ... 2.2).contains($0) })
        #expect((0.45 ... 0.6).contains(curve.typicalFactor))
    }

    @Test func darkeningHalvesABrightenedTexel() {
        // A synthetic LOD texel at 0.4 came from land at about 0.2.
        let source = TerrainLODBrightness.vanilla.darkened(0.4)
        #expect(abs(source - 0.21) < 0.01)
    }

    @Test func identityKeepsTheTexture() {
        let curve = TerrainLODBrightness.identity
        #expect(curve.darkened(0.37) == 0.37)
        #expect(curve.typicalFactor == 1)
    }
}
