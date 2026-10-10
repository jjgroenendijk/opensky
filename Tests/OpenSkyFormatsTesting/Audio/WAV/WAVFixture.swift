// RIFF/WAVE bytes built in code (docs/formats/wav.md), never from a game file.

import Foundation

public enum WAVFixture {
    public static func file(
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
        return file(
            channels: channels, sampleRate: sampleRate, bits: bits,
            payload: payload, tag: tag, extraChunks: extraChunks
        )
    }

    public static func file(
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
