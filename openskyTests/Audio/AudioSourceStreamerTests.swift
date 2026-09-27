// Pure PCM-packing coverage for the streaming scheduler: the mono downmix the
// environment node requires and the interleaved-to-deinterleaved buffer pack.
// The decode loop itself is exercised against the real install by the
// `openskycli audio sweep` gate (no WMA fixture may enter the repository).

import AVFAudio
@testable import opensky
import Testing

struct AudioSourceStreamerTests {
    @Test
    func monoDownmixAveragesChannels() {
        let interleaved: [Float] = [1, 0, 0.5, 0.5, -1, 1]
        let mono = AudioSourceStreamer.monoDownmix(interleaved, channelCount: 2)
        #expect(mono == [0.5, 0.5, 0])
    }

    @Test
    func monoInputPassesThrough() {
        let samples: [Float] = [0.25, -0.25]
        #expect(AudioSourceStreamer.monoDownmix(samples, channelCount: 1) == samples)
    }

    /// Rewind policy at end of file: only a looping source whose pass produced
    /// PCM and that was not asked to stop starts the file over. The "produced
    /// PCM" clause is what keeps an undecodable file from spinning the decode
    /// queue forever.
    @Test
    func rewindsOnlyForAProductiveUnstoppedLoop() {
        #expect(AudioSourceStreamer.shouldRewind(
            loops: true, passProducedSamples: true, stopped: false
        ))
        #expect(!AudioSourceStreamer.shouldRewind(
            loops: false, passProducedSamples: true, stopped: false
        ))
        #expect(!AudioSourceStreamer.shouldRewind(
            loops: true, passProducedSamples: false, stopped: false
        ))
        #expect(!AudioSourceStreamer.shouldRewind(
            loops: true, passProducedSamples: true, stopped: true
        ))
    }

    @Test
    func makeBufferDownmixesToMonoFormat() throws {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        )
        let buffer = try #require(AudioSourceStreamer.makeBuffer(
            samples: [1, 0, 0, 1, -0.5, -0.5],
            sourceChannelCount: 2,
            downmixToMono: true,
            format: format
        ))
        #expect(buffer.frameLength == 3)
        let channel = try #require(buffer.floatChannelData?[0])
        #expect(channel[0] == 0.5)
        #expect(channel[1] == 0.5)
        #expect(channel[2] == -0.5)
    }

    @Test
    func makeBufferDeinterleavesStereo() throws {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        )
        let buffer = try #require(AudioSourceStreamer.makeBuffer(
            samples: [1, -1, 0.5, -0.5],
            sourceChannelCount: 2,
            downmixToMono: false,
            format: format
        ))
        #expect(buffer.frameLength == 2)
        let channels = try #require(buffer.floatChannelData)
        #expect(channels[0][0] == 1)
        #expect(channels[0][1] == 0.5)
        #expect(channels[1][0] == -1)
        #expect(channels[1][1] == -0.5)
    }

    @Test
    func makeBufferRejectsRaggedInput() throws {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        )
        // Five samples cannot fill whole stereo frames.
        #expect(AudioSourceStreamer.makeBuffer(
            samples: [1, 2, 3, 4, 5],
            sourceChannelCount: 2,
            downmixToMono: false,
            format: format
        ) == nil)
        // Channel-count mismatch with the format is rejected too.
        #expect(AudioSourceStreamer.makeBuffer(
            samples: [1, 2],
            sourceChannelCount: 1,
            downmixToMono: false,
            format: format
        ) == nil)
    }
}
