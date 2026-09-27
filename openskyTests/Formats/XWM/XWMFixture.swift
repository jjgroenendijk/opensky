// Synthetic xWMA byte builder shared by the `.xwm` framing tests. Fixtures
// are built in code — never extracted game files (AGENTS.md "Legal & IP
// boundary"). The payload bytes are counter values, not audio.
//
// Layout follows the Microsoft xWMA description on MultimediaWiki
// (https://wiki.multimedia.cx/index.php/Microsoft_xWMA) and WAVEFORMATEX
// (Microsoft mmeapi.h); see docs/formats/xwm.md.

import Foundation
@testable import opensky

enum XWMFixture {
    /// WAVE_FORMAT_WMAUDIO2, the tag vanilla Skyrim SE `.xwm` files carry.
    static let formatTagWMAv2: UInt16 = 0x0161
    /// Packet size vanilla files use for `nBlockAlign`.
    static let defaultBlockAlign: UInt16 = 2230

    /// One RIFF chunk: four-character id, UInt32 size, body, pad to even.
    static func chunk(_ identifier: String, _ body: Data) -> Data {
        var out = Data(identifier.utf8)
        out.appendUInt32(UInt32(body.count))
        out.append(body)
        if body.count % 2 == 1 {
            out.append(0)
        }
        return out
    }

    /// WAVEFORMATEX body of a `fmt ` chunk.
    static func formatBody(
        formatTag: UInt16 = formatTagWMAv2,
        channelCount: UInt16 = 2,
        sampleRate: UInt32 = 44100,
        averageBytesPerSecond: UInt32 = 6000,
        blockAlign: UInt16 = defaultBlockAlign,
        bitsPerSample: UInt16 = 16,
        extraData: Data = Data()
    ) -> Data {
        var out = Data()
        out.appendUInt16(formatTag)
        out.appendUInt16(channelCount)
        out.appendUInt32(sampleRate)
        out.appendUInt32(averageBytesPerSecond)
        out.appendUInt16(blockAlign)
        out.appendUInt16(bitsPerSample)
        out.appendUInt16(UInt16(extraData.count))
        out.append(extraData)
        return out
    }

    /// `dpds` body: cumulative decoded byte counts, one UInt32 per packet.
    static func packetTableBody(_ entries: [UInt32]) -> Data {
        var out = Data()
        for entry in entries {
            out.appendUInt32(entry)
        }
        return out
    }

    /// Payload bytes tagged by packet index so tests can assert slicing.
    static func payload(packetCount: Int, blockAlign: Int = Int(defaultBlockAlign)) -> Data {
        var out = Data()
        for index in 0 ..< packetCount {
            out.append(Data(
                repeating: UInt8(truncatingIfNeeded: index),
                count: blockAlign
            ))
        }
        return out
    }

    /// Wraps already-built chunks in a RIFF/XWMA header. `riffSize` overrides
    /// the size field so tests can claim more bytes than the buffer holds.
    static func container(
        magic: String = "RIFF",
        formType: String = "XWMA",
        chunks: Data,
        riffSize: UInt32? = nil
    ) -> Data {
        var out = Data(magic.utf8)
        out.appendUInt32(riffSize ?? UInt32(4 + chunks.count))
        out.append(Data(formType.utf8))
        out.append(chunks)
        return out
    }

    /// A well-formed two-channel 44.1 kHz WMAv2 file whose `dpds` table has
    /// one entry per packet, each packet decoding to `decodedBytesPerPacket`.
    static func file(
        packetCount: Int = 3,
        formatTag: UInt16 = formatTagWMAv2,
        blockAlign: UInt16 = defaultBlockAlign,
        channelCount: UInt16 = 2,
        bitsPerSample: UInt16 = 16,
        decodedBytesPerPacket: UInt32 = 40960
    ) -> Data {
        let entries = (1 ... max(1, packetCount)).map { UInt32($0) * decodedBytesPerPacket }
        var chunks = chunk("fmt ", formatBody(
            formatTag: formatTag,
            channelCount: channelCount,
            blockAlign: blockAlign,
            bitsPerSample: bitsPerSample
        ))
        chunks.append(chunk("dpds", packetTableBody(Array(entries.prefix(packetCount)))))
        chunks.append(chunk("data", payload(
            packetCount: packetCount,
            blockAlign: Int(blockAlign)
        )))
        return container(chunks: chunks)
    }
}
