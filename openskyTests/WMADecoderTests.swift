// WMADecoder tests over synthetic headers and payloads (WMADecoderFixture). These cover
// the header contract, the typed error surface and the requirement that malformed input
// never crashes. Decoding a real payload is a probe against the player's own install, not
// a committed test: no game audio enters this repository.

import Foundation
@testable import opensky
import Testing

struct WMADecoderTests {
    @Test func rejectsForeignFormatTag() {
        let parameters = WMADecoderFixture.parameters(formatTag: 0x0001)
        #expect(throws: WMADecoderError.unsupportedFormatTag(0x0001)) {
            _ = try WMADecoder(parameters: parameters)
        }
    }

    @Test func rejectsZeroChannels() {
        #expect(throws: WMADecoderError.self) {
            _ = try WMADecoder(parameters: WMADecoderFixture.parameters(channelCount: 0))
        }
    }

    @Test func rejectsAbsurdChannelCount() {
        #expect(throws: WMADecoderError.self) {
            _ = try WMADecoder(parameters: WMADecoderFixture.parameters(channelCount: 4096))
        }
    }

    @Test(arguments: [0, -1, 1_000_000]) func rejectsImplausibleSampleRate(rate: Int) {
        #expect(throws: WMADecoderError.self) {
            _ = try WMADecoder(parameters: WMADecoderFixture.parameters(sampleRate: rate))
        }
    }

    @Test func rejectsZeroBlockAlign() {
        #expect(throws: WMADecoderError.self) {
            _ = try WMADecoder(parameters: WMADecoderFixture.parameters(blockAlign: 0))
        }
    }

    @Test func validationHappensBeforeAnyAllocation() throws {
        // A rejected header must not depend on ffmpeg at all, so the error is specific.
        let parameters = WMADecoderFixture.parameters(formatTag: 0x0162)
        do {
            _ = try WMADecoder(parameters: parameters)
            Issue.record("expected the WMAPro format tag to be rejected")
        } catch let error as WMADecoderError {
            #expect(error == .unsupportedFormatTag(0x0162))
        }
    }

    @Test func opensAgainstTheVendoredWMAv2Decoder() throws {
        let decoder = try WMADecoder(parameters: WMADecoderFixture.parameters())
        #expect(decoder.outputSampleRate == 44100)
        #expect(decoder.outputChannelCount == 2)
    }

    @Test func acceptsMonoAndCommonSampleRates() throws {
        let parameters = WMADecoderFixture.parameters(
            channelCount: 1,
            sampleRate: 32000,
            blockAlign: 743
        )
        let decoder = try WMADecoder(parameters: parameters)
        #expect(decoder.outputChannelCount == 1)
        #expect(decoder.outputSampleRate == 32000)
    }

    @Test func emptyPacketProducesNoSamples() throws {
        let decoder = try WMADecoder(parameters: WMADecoderFixture.parameters())
        #expect(try decoder.decode(packet: Data()).isEmpty)
    }

    @Test func garbagePacketsNeverCrash() throws {
        let decoder = try WMADecoder(parameters: WMADecoderFixture.parameters())
        for size in [1, 16, 512, 2972] {
            let packet = WMADecoderFixture.noisePacket(byteCount: size)
            // Either outcome is acceptable; crashing or reading out of bounds is not.
            _ = try? decoder.decode(packet: packet)
        }
        decoder.reset()
        _ = try? decoder.flush()
    }

    @Test func flushOnAnUntouchedDecoderYieldsNothing() throws {
        let decoder = try WMADecoder(parameters: WMADecoderFixture.parameters())
        #expect(try decoder.flush().isEmpty)
    }

    @Test func repeatedConstructionAndTeardownStaysStable() throws {
        // Exercises the allocate/free pairing many times over; a lifetime bug shows up here
        // as a crash or as unbounded growth under `leaks`.
        for _ in 0 ..< 200 {
            let decoder = try WMADecoder(parameters: WMADecoderFixture.parameters())
            _ = try? decoder.decode(packet: WMADecoderFixture.noisePacket(byteCount: 64))
            _ = try? decoder.flush()
        }
    }

    @Test func rejectsMoreChannelsThanWMAv2Defines() {
        // WMA carries at most two channels, so this header passes OpenSky's own validation
        // and is refused by avcodec_open2 instead.
        #expect(throws: WMADecoderError.self) {
            _ = try WMADecoder(parameters: WMADecoderFixture.parameters(channelCount: 6))
        }
    }

    @Test func failedInitialisationLeavesNothingBehind() {
        // The same rejection in a loop, so the throw-after-allocation path runs repeatedly:
        // a missed avcodec_free_context would show up here under `leaks`.
        for _ in 0 ..< 200 {
            _ = try? WMADecoder(parameters: WMADecoderFixture.parameters(channelCount: 6))
        }
    }

    @Test func staticDecodeReportsContainerFormat() throws {
        let parameters = WMADecoderFixture.parameters()
        let audio = try WMADecoder.decode(packets: [], parameters: parameters)
        #expect(audio.sampleRate == 44100)
        #expect(audio.channelCount == 2)
        #expect(audio.samples.isEmpty)
    }
}

struct DecodedAudioTests {
    @Test func framesAndDurationFollowChannelCount() {
        let audio = DecodedAudio(
            sampleRate: 48000,
            channelCount: 2,
            samples: [Float](repeating: 0, count: 9600)
        )
        #expect(audio.frameCount == 4800)
        #expect(abs(audio.duration - 0.1) < 1e-6)
    }

    @Test func degenerateFormatDoesNotDivideByZero() {
        let audio = DecodedAudio(sampleRate: 0, channelCount: 0, samples: [1, 2, 3])
        #expect(audio.frameCount == 0)
        #expect(audio.duration == 0)
    }
}
