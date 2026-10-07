// The audio cache converter over synthetic 16-bit sounds: ALAC decodes back to
// exactly the source samples, and long sounds are left to stream.

import AVFAudio
import FormatsTesting
import Foundation
import OpenSkyAssetCache
@testable import OpenSkyAudio
import OpenSkyFormatsAudio
import Testing

struct CachedAudioConverterTests {
    private static func ramp(frames: Int, channels: Int) -> [Int16] {
        (0 ..< frames * channels).map { Int16(truncatingIfNeeded: ($0 * 977) % 65536 - 32768) }
    }

    @Test(arguments: [1, 2])
    func alacDecodesToTheExactSourceSamples(channels: Int) throws {
        let samples = Self.ramp(frames: 5000, channels: channels)
        let wav = WAVFixture.file(channels: channels, sampleRate: 22050, bits: 16, samples: samples)
        let payload = try #require(try CachedAudioConverter().convert(
            path: "sound\\fx\\a.wav",
            bytes: wav,
            preset: .balanced
        ))
        let decoded = try AssetCacheDecoder.cachedAudio.decode(payload)
        let source = try WAVFile(data: wav)
        #expect(decoded.sampleRate == 22050)
        #expect(decoded.channelCount == channels)
        #expect(decoded.samples == source.samples)
    }

    @Test func aSoundLongerThanTheLimitIsNotStored() throws {
        let rate = 1000
        let frames = Int(CachedAudioConverter.maximumSeconds) * rate + 1
        let wav = WAVFixture.file(
            channels: 1,
            sampleRate: rate,
            bits: 16,
            samples: Self.ramp(frames: frames, channels: 1)
        )
        #expect(try CachedAudioConverter().convert(
            path: "music\\a.wav",
            bytes: wav,
            preset: .balanced
        ) == nil)
    }

    @Test func theConverterReadsWavAndXwmOnly() {
        let converter = CachedAudioConverter()
        #expect(converter.accepts(path: "sound\\fx\\a.wav"))
        #expect(converter.accepts(path: "sound\\fx\\a.xwm"))
        #expect(!converter.accepts(path: "sound\\voice\\a.fuz"))
    }

    @Test func aCachedSoundPlaysFromOneBuffer() throws {
        let audio = DecodedAudio(
            sampleRate: 8000,
            channelCount: 2,
            samples: [0.5, -0.5, 0.25, 0.75]
        )
        let mono = try WorldAudioEngine.makeBuffer(decoded: audio, downmixToMono: true)
        #expect(mono.frameLength == 2)
        #expect(mono.floatChannelData?[0][1] == 0.5)
    }
}
