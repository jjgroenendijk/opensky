// RIFF/WAVE framing and PCM widening over synthetic buffers only — never an
// extracted game file (AGENTS.md "Legal & IP boundary"). Layout source:
// Microsoft "Multimedia Programming Interface and Data Specifications 1.0";
// see docs/formats/wav.md.

import Foundation
@testable import opensky
import Testing

struct WAVFileTests {
    @Test func decodesSixteenBitMono() throws {
        let file = try WAVFile(
            data: Self.wav(channels: 1, sampleRate: 22050, bits: 16, samples: [
                0, 32767, -32768, -1
            ])
        )

        #expect(file.format.formatTag == 1)
        #expect(file.format.channelCount == 1)
        #expect(file.format.sampleRate == 22050)
        #expect(file.format.bitsPerSample == 16)
        #expect(file.frameCount == 4)
        #expect(file.samples[0] == 0)
        #expect(abs(file.samples[1] - 0.99997) < 0.0001)
        #expect(file.samples[2] == -1)
        #expect(abs(file.samples[3] + 0.00003) < 0.0001)
    }

    @Test func decodesStereoInterleaved() throws {
        let file = try WAVFile(
            data: Self.wav(channels: 2, sampleRate: 44100, bits: 16, samples: [
                16384, -16384, 0, 32767
            ])
        )

        #expect(file.format.channelCount == 2)
        #expect(file.frameCount == 2)
        #expect(file.samples[0] == 0.5)
        #expect(file.samples[1] == -0.5)
    }

    /// Eight-bit WAVE samples are unsigned with 128 as silence, unlike the
    /// signed sixteen-bit case.
    @Test func decodesEightBitUnsigned() throws {
        var payload = Data()
        payload.append(contentsOf: [0, 128, 255])
        let file = try WAVFile(
            data: Self.wav(channels: 1, sampleRate: 8000, bits: 8, payload: payload)
        )

        #expect(file.samples[0] == -1)
        #expect(file.samples[1] == 0)
        #expect(abs(file.samples[2] - 0.9922) < 0.0001)
    }

    @Test func skipsUnknownChunksAndOddSizePadding() throws {
        var extra = Data("LIST".utf8)
        extra.appendUInt32(3)
        extra.append(contentsOf: [1, 2, 3, 0]) // 3 bytes plus RIFF pad
        let file = try WAVFile(
            data: Self.wav(
                channels: 1, sampleRate: 8000, bits: 16, samples: [1234], extraChunks: extra
            )
        )

        #expect(file.frameCount == 1)
    }

    @Test func nonPCMTagIsDeclinedRatherThanGuessedAt() {
        #expect(throws: WAVError.self) {
            _ = try WAVFile(
                data: Self.wav(channels: 1, sampleRate: 8000, bits: 16, samples: [0], tag: 3)
            )
        }
        #expect(throws: WAVError.self) {
            _ = try WAVFile(
                data: Self.wav(
                    channels: 1, sampleRate: 8000, bits: 24, payload: Data(count: 3)
                )
            )
        }
    }

    @Test func malformedContainersThrowInsteadOfCrashing() {
        #expect(throws: WAVError.self) { _ = try WAVFile(data: Data()) }
        #expect(throws: WAVError.self) {
            _ = try WAVFile(data: Data("RIFX".utf8) + Data(count: 8))
        }
        // RIFF/XWMA is a different form and must not be read as WAVE.
        var xwma = Data("RIFF".utf8)
        xwma.appendUInt32(4)
        xwma.append(Data("XWMA".utf8))
        #expect(throws: WAVError.self) { _ = try WAVFile(data: xwma) }
        // WAVE form with no `data` chunk.
        #expect(throws: WAVError.self) {
            _ = try WAVFile(data: Self.wav(channels: 1, sampleRate: 8000, bits: 16, payload: nil))
        }
    }

    @Test func formSniffSeparatesWAVEFromXWMA() {
        #expect(WorldAudioEngine.isWAV(
            Self.wav(channels: 1, sampleRate: 8000, bits: 16, samples: [0])
        ))
        var xwma = Data("RIFF".utf8)
        xwma.appendUInt32(4)
        xwma.append(Data("XWMA".utf8))
        #expect(!WorldAudioEngine.isWAV(xwma))
        #expect(!WorldAudioEngine.isWAV(Data(count: 4)))
    }

    // MARK: - Fixture

    private static func wav(
        channels: Int,
        sampleRate: Int,
        bits: Int,
        samples: [Int16],
        tag: UInt16 = 1,
        extraChunks: Data = Data()
    ) -> Data {
        var payload = Data()
        for sample in samples {
            payload.appendUInt16(UInt16(bitPattern: sample))
        }
        return wav(
            channels: channels, sampleRate: sampleRate, bits: bits,
            payload: payload, tag: tag, extraChunks: extraChunks
        )
    }

    private static func wav(
        channels: Int,
        sampleRate: Int,
        bits: Int,
        payload: Data?,
        tag: UInt16 = 1,
        extraChunks: Data = Data()
    ) -> Data {
        var format = Data()
        format.appendUInt16(tag)
        format.appendUInt16(UInt16(channels))
        format.appendUInt32(UInt32(sampleRate))
        format.appendUInt32(UInt32(sampleRate * channels * bits / 8))
        format.appendUInt16(UInt16(channels * bits / 8))
        format.appendUInt16(UInt16(bits))

        var body = Data("WAVE".utf8)
        body += Data("fmt ".utf8)
        body.appendUInt32(UInt32(format.count))
        body += format
        body += extraChunks
        if let payload {
            body += Data("data".utf8)
            body.appendUInt32(UInt32(payload.count))
            body += payload
            if payload.count % 2 == 1 {
                body.append(0)
            }
        }
        var out = Data("RIFF".utf8)
        out.appendUInt32(UInt32(body.count))
        out += body
        return out
    }
}
