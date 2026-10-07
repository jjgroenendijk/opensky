// Band spectral distortion over synthetic signals: identical audio, broadband
// noise, silence, and a known shift.

import Foundation
import OpenSkyAssetCache
@testable import OpenSkyAudio
import Testing

struct SpectralDistortionTests {
    /// A repeatable noise source, so the tests do not depend on a random seed.
    private static func noise(count: Int, amplitude: Float, seed: UInt64) -> [Float] {
        var state = seed
        return (0 ..< count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * amplitude
        }
    }

    private static func mono(_ samples: [Float]) -> DecodedAudio {
        DecodedAudio(sampleRate: 44100, channelCount: 1, samples: samples)
    }

    @Test func identicalAudioHasNoDistortion() {
        let audio = Self.mono(Self.noise(count: 44100, amplitude: 0.5, seed: 1))
        let result = SpectralDistortionMeter.measure(reference: audio, candidate: audio)
        #expect(result.frames > 80)
        #expect(result.meanDB < 1e-6)
        #expect(result.isTransparent)
    }

    @Test func addedNoiseAtMinus20DBIsNotTransparent() {
        let clean = Self.noise(count: 44100, amplitude: 0.5, seed: 1)
        let hiss = Self.noise(count: 44100, amplitude: 0.5, seed: 2)
        let tone = (0 ..< 44100).map { Float(sin(Double($0) * 0.05)) * 0.5 }
        let reference = zip(clean, tone).map { $0 * 0.01 + $1 }
        let candidate = zip(reference, hiss).map { $0 + $1 * 0.1 }
        let result = SpectralDistortionMeter.measure(
            reference: Self.mono(reference), candidate: Self.mono(candidate)
        )
        #expect(result.meanDB > 1)
        #expect(!result.isTransparent)
    }

    @Test func silenceIsNotMeasured() {
        let audio = Self.mono([Float](repeating: 0, count: 8192))
        let result = SpectralDistortionMeter.measure(reference: audio, candidate: audio)
        #expect(result.frames == 0)
        #expect(result.bestLag == 0)
        #expect(result.isTransparent)
    }

    @Test func theBestLagFindsAShiftedCopy() {
        let reference = Self.noise(count: 20000, amplitude: 0.5, seed: 3)
        let delayed = [Float](repeating: 0, count: 300) + reference
        #expect(SpectralDistortionMeter.bestLag(reference, delayed) == 300)
    }

    @Test func theSampleIsEvenlySpacedAndRepeatable() {
        let paths = (0 ..< 10).map { "sound\\fx\\wpn\\a\($0).wav" } + ["music\\b.xwm"]
        let sample = AACTransparency.sample(paths: paths.reversed(), perCategory: 5)
        #expect(sample[.effects] == (0 ..< 5).map { "sound\\fx\\wpn\\a\($0 * 2).wav" })
        #expect(sample[.music] == ["music\\b.xwm"])
    }
}
