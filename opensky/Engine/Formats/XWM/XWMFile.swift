// xWMA container framing for Skyrim SE `.xwm` audio: the RIFF/XWMA header,
// the `fmt ` WAVEFORMATEX chunk, the `dpds` decoded-packet-cumulative-size
// table, and the `data` payload. This type frames and validates only — it
// never decodes WMA. The codec parameters and the raw payload are handed to
// the decoder (milestone 9.1.1).
//
// References:
//   Microsoft xWMA, MultimediaWiki
//     https://wiki.multimedia.cx/index.php/Microsoft_xWMA
//     (RIFF/XWMA form, 18-byte `fmt `, `dpds` as "the i-th integer equals the
//     total number of bytes accumulated after the i-th packet ... has been
//     decoded", `data` payload in nBlockAlign-sized packets)
//   FFmpeg libavformat/xwma.c (read as documentation, not transcribed)
//     https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/xwma.c
//     (magic + form type checks, dpds element width and duplicate-chunk
//     rejection, packets sized by nBlockAlign, duration from the last dpds
//     entry divided by channels * bitsPerSample / 8)
//   Microsoft WAVEFORMATEX (mmeapi.h) for the `fmt ` field order and widths
//     https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/ns-mmeapi-waveformatex
//   Microsoft "Multimedia Programming Interface and Data Specifications 1.0"
//     for RIFF chunk framing (four-byte id, UInt32 size, pad to even length)
// Layout documented in docs/formats/xwm.md.

import Foundation

nonisolated enum XWMError: Error, Equatable {
    /// Input violates the documented layout.
    case malformed(String)
    /// Structurally valid xWMA carrying a codec OpenSky does not read.
    case unsupported(String)
}

/// WAVEFORMATEX parameters a WMA decoder needs, lifted out of the `fmt `
/// chunk. Field names follow the Microsoft struct members they come from.
nonisolated struct XWMCodecParameters: Equatable {
    /// `wFormatTag`. `0x0161` is WAVE_FORMAT_WMAUDIO2 (WMAv2).
    let formatTag: UInt16
    /// `nChannels`.
    let channelCount: Int
    /// `nSamplesPerSec`, in hertz.
    let sampleRate: Int
    /// `nAvgBytesPerSec`. Times eight this is the nominal bit rate.
    let averageBytesPerSecond: Int
    /// `nBlockAlign` — the size of one encoded xWMA packet in the payload.
    let blockAlign: Int
    /// `wBitsPerSample` of the *decoded* PCM, not of the encoded packets.
    let bitsPerSample: Int
    /// The `cbSize` trailer of the `fmt ` chunk. Vanilla `.xwm` carries none;
    /// see docs/formats/xwm.md for the decoder-side extradata policy.
    let extraData: Data

    /// Bytes one decoded PCM frame (one sample across all channels) occupies.
    /// This is the divisor xwma.c applies to the last `dpds` entry to get a
    /// sample count.
    var bytesPerDecodedFrame: Int {
        channelCount * bitsPerSample / 8
    }

    /// Nominal bit rate in bits per second.
    var bitRate: Int {
        averageBytesPerSecond * 8
    }
}

/// A framed `.xwm` file: codec parameters, the packet-boundary table, and the
/// encoded payload. Parsing is bounds-checked throughout; malformed input
/// throws `XWMError` rather than trapping.
nonisolated struct XWMFile {
    private enum Layout {
        /// WAVE_FORMAT_WMAUDIO2 — the only tag vanilla Skyrim SE `.xwm` uses.
        static let formatTagWMAv2: UInt16 = 0x0161
        /// WAVE_FORMAT_WMAUDIO3 (WMA Pro). Recognized, declined.
        static let formatTagWMAPro: UInt16 = 0x0162
        /// WAVE_FORMAT_WMAUDIO_LOSSLESS. Recognized, declined.
        static let formatTagWMALossless: UInt16 = 0x0163
        /// Sanity bound on `nChannels`; xWMA tops out at 6 (WMA Pro).
        static let maxChannelCount = 8
        /// Sanity bound on `nSamplesPerSec`.
        static let maxSampleRate = 384_000
    }

    let codec: XWMCodecParameters
    /// `dpds` contents: entry `index` is the total number of decoded PCM bytes
    /// accumulated once packet `index` has been decoded. Empty when the file
    /// carries no `dpds` chunk.
    let packetCumulativeDecodedBytes: [UInt32]

    private let source: Data
    /// Byte range of the `data` chunk body within `source`.
    private let payloadRange: Range<Int>

    init(data: Data) throws {
        source = data
        let chunks = try XWMChunkScan(data: data)
        codec = try Self.makeCodecParameters(chunks.format)
        packetCumulativeDecodedBytes = chunks.packetTable
        payloadRange = chunks.payloadRange

        switch codec.formatTag {
        case Layout.formatTagWMAv2:
            break
        case Layout.formatTagWMAPro, Layout.formatTagWMALossless:
            throw XWMError.unsupported(
                "format tag \(Self.hex(codec.formatTag)) (WMA Pro / WMA Lossless)"
            )
        default:
            throw XWMError.unsupported("format tag \(Self.hex(codec.formatTag))")
        }
    }

    private static func hex(_ value: UInt16) -> String {
        "0x" + String(format: "%04X", value)
    }

    /// Validates the raw `fmt ` fields. WAVEFORMATEX member order and widths:
    /// `wFormatTag`, `nChannels`, `nSamplesPerSec`, `nAvgBytesPerSec`,
    /// `nBlockAlign`, `wBitsPerSample`, `cbSize` (Microsoft mmeapi.h).
    private static func makeCodecParameters(
        _ format: XWMChunkScan.RawFormat
    ) throws -> XWMCodecParameters {
        guard (1 ... Layout.maxChannelCount).contains(format.channelCount) else {
            throw XWMError.malformed("nChannels \(format.channelCount) out of range")
        }
        guard (1 ... Layout.maxSampleRate).contains(format.sampleRate) else {
            throw XWMError.malformed("nSamplesPerSec \(format.sampleRate) out of range")
        }
        guard format.blockAlign > 0 else {
            throw XWMError.malformed("nBlockAlign is zero")
        }
        guard format.bitsPerSample > 0, format.bitsPerSample % 8 == 0 else {
            throw XWMError.malformed(
                "wBitsPerSample \(format.bitsPerSample) is not a whole number of bytes"
            )
        }
        return XWMCodecParameters(
            formatTag: format.formatTag,
            channelCount: format.channelCount,
            sampleRate: format.sampleRate,
            averageBytesPerSecond: format.averageBytesPerSecond,
            blockAlign: format.blockAlign,
            bitsPerSample: format.bitsPerSample,
            extraData: format.extraData
        )
    }
}

nonisolated extension XWMFile {
    /// Encoded payload: the `data` chunk body, a sequence of `blockAlign`
    /// sized packets. Copied out on demand so a framed file stays cheap.
    var payload: Data {
        source.subdata(
            in: (source.startIndex + payloadRange.lowerBound)
                ..< (source.startIndex + payloadRange.upperBound)
        )
    }

    var payloadByteCount: Int {
        payloadRange.count
    }

    /// Packets in the payload. The final packet may be short; xwma.c clamps
    /// its read to what is left, so a partial trailing packet is framed, not
    /// dropped.
    var packetCount: Int {
        (payloadByteCount + codec.blockAlign - 1) / codec.blockAlign
    }

    /// One encoded packet, or `nil` when `index` is out of range. Streaming
    /// callers use this instead of holding `payload`.
    func packet(at index: Int) -> Data? {
        guard index >= 0, index < packetCount else { return nil }
        let start = payloadRange.lowerBound + index * codec.blockAlign
        let end = min(start + codec.blockAlign, payloadRange.upperBound)
        return source.subdata(
            in: (source.startIndex + start) ..< (source.startIndex + end)
        )
    }

    /// Total decoded PCM bytes the container claims, from the last `dpds`
    /// entry. `nil` when the file carries no packet table.
    var declaredDecodedByteCount: Int? {
        packetCumulativeDecodedBytes.last.map(Int.init)
    }

    /// Decoded PCM sample frames the container claims (xwma.c duration math:
    /// last `dpds` entry / (channels * bitsPerSample / 8)).
    var declaredSampleCount: Int? {
        let bytesPerFrame = codec.bytesPerDecodedFrame
        guard bytesPerFrame > 0, let decoded = declaredDecodedByteCount else { return nil }
        return decoded / bytesPerFrame
    }

    /// Playing time in seconds from the packet table, or `nil` without one.
    var declaredDuration: Double? {
        guard codec.sampleRate > 0, let samples = declaredSampleCount else { return nil }
        return Double(samples) / Double(codec.sampleRate)
    }

    /// Whether the packet table has one entry per payload packet. Advisory:
    /// a mismatch is reported by the sweep rather than rejected, because a
    /// file can legitimately carry no `dpds` chunk at all.
    var isPacketTableConsistent: Bool {
        packetCumulativeDecodedBytes.isEmpty
            || packetCumulativeDecodedBytes.count == packetCount
    }
}
