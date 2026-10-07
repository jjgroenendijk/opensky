// CAF write and read through AudioToolbox, over a synthetic tone.

import Foundation
@testable import OpenSkyAudio
import Testing

struct CAFAudioCodecTests {
    /// One second of a 440 Hz stereo tone at 44.1 kHz, quiet enough for 16 bits.
    private static let tone: DecodedAudio = {
        let rate = 44100
        let samples = (0 ..< rate).flatMap { frame -> [Float] in
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / Double(rate)) * 0.5)
            return [value, -value]
        }
        return DecodedAudio(sampleRate: rate, channelCount: 2, samples: samples)
    }()

    private func roundTrip(_ format: CAFAudioFormat) throws -> DecodedAudio {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-caf-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try CAFAudioCodec.write(Self.tone, to: url, format: format)
        return try CAFAudioCodec.read(url)
    }

    @Test func pcmIsExact() throws {
        #expect(try roundTrip(.pcmFloat32) == Self.tone)
    }

    @Test func alacKeepsSixteenBitPrecision() throws {
        let decoded = try roundTrip(.alac)
        #expect(decoded.frameCount == Self.tone.frameCount)
        let worst = zip(decoded.samples, Self.tone.samples).map { abs($0 - $1) }.max() ?? 1
        #expect(worst <= 1.0 / 32768 + 1e-6)
    }

    @Test func aacKeepsLengthAndRate() throws {
        let decoded = try roundTrip(.aac)
        #expect(decoded.sampleRate == 44100)
        #expect(decoded.channelCount == 2)
        #expect(abs(decoded.frameCount - Self.tone.frameCount) < 2048)
    }

    @Test func aacFollowsTheBitRate() throws {
        var state: UInt32 = 1
        let noise = (0 ..< 441_000).map { _ -> Float in
            state = state &* 1_664_525 &+ 1_013_904_223
            return (Float(state >> 8) / Float(1 << 24) - 0.5) * 0.5
        }
        let audio = DecodedAudio(sampleRate: 44100, channelCount: 1, samples: noise)
        let sizes = try [32000, 128_000].map { rate in
            let url = FileManager.default.temporaryDirectory
                .appending(path: "opensky-caf-\(UUID().uuidString).caf")
            defer { try? FileManager.default.removeItem(at: url) }
            try CAFAudioCodec.write(audio, to: url, format: .aac, aacBitRatePerChannel: rate)
            return try Data(contentsOf: url).count
        }
        // Ten seconds at 128 kbps is 160 KB of audio; the header adds about 28 KB.
        #expect(sizes[1] > 140_000 && sizes[1] < 220_000, "\(sizes)")
        #expect(sizes[1] > sizes[0] * 2, "\(sizes)")
    }

    @Test func emptyAudioThrows() {
        let url = FileManager.default.temporaryDirectory.appending(path: "opensky-empty.caf")
        #expect(throws: CAFAudioCodecError.emptyAudio) {
            try CAFAudioCodec.write(
                DecodedAudio(sampleRate: 44100, channelCount: 2, samples: []), to: url,
                format: .pcmFloat32
            )
        }
    }
}
