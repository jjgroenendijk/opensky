// The terrain LOD curve: a texture the Creation Kit brightened, darkened as the
// landscape noise shader does, gives back the source brightness.

@testable import OpenSkyRenderCore
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

    @Test func fitRecoversTheGainOfOneWorld() {
        // A worldspace brightened less than vanilla, like the Dawnguard ones.
        let curve = TerrainLODBrightness(gain: 2.0, exponent: TerrainLODBrightness.vanilla.exponent)
        let samples = (0 ..< 40).map { index -> SIMD2<Float> in
            let source = 0.08 + Float(index) * 0.006
            return SIMD2(source, curve.brightened(source))
        }
        let fitted = TerrainLODBrightness.fitted(samples: samples)
        #expect(abs(fitted.gain - 2.0) < 0.001)
        #expect(abs(fitted.darkened(curve.brightened(0.2)) - 0.2) < 0.001)
    }

    @Test func fewSamplesKeepTheVanillaCurve() {
        let samples = [SIMD2<Float>](repeating: SIMD2(0.2, 0.3), count: 3)
        #expect(TerrainLODBrightness.fitted(samples: samples) == .vanilla)
    }

    @Test func brokenDataIsClamped() {
        let samples = [SIMD2<Float>](repeating: SIMD2(0.2, 0.001), count: 30)
        #expect(TerrainLODBrightness.fitted(samples: samples).gain == 0.5)
    }
}
