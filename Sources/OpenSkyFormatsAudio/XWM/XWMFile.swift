// xWMA container framing: the `fmt ` WAVEFORMATEX chunk, the `dpds` table of
// cumulative decoded sizes, and the `data` payload. It never decodes WMA; the
// decoder gets the codec parameters and the raw payload.
// Layout and sources: docs/formats/xwm.md.

import Foundation

nonisolated public enum XWMError: Error, Equatable, Sendable {
    /// Input violates the documented layout.
    case malformed(String)
    /// Structurally valid xWMA carrying a codec OpenSky does not read.
    case unsupported(String)
}

/// WAVEFORMATEX parameters a WMA decoder needs, lifted out of the `fmt `
/// chunk. Field names follow the Microsoft struct members they come from.
nonisolated public struct XWMCodecParameters: Equatable, Sendable {
    /// `wFormatTag`. `0x0161` is WAVE_FORMAT_WMAUDIO2 (WMAv2).
    public let formatTag: UInt16
    /// `nChannels`.
    public let channelCount: Int
    /// `nSamplesPerSec`, in hertz.
    public let sampleRate: Int
    /// `nAvgBytesPerSec`. Times eight this is the nominal bit rate.
    public let averageBytesPerSecond: Int
    /// `nBlockAlign` — the size of one encoded xWMA packet in the payload.
    public let blockAlign: Int
    /// `wBitsPerSample` of the *decoded* PCM, not of the encoded packets.
    public let bitsPerSample: Int
    /// The `cbSize` trailer of the `fmt ` chunk. Vanilla `.xwm` carries none;
    /// see docs/formats/xwm.md for the decoder-side extradata policy.
    public let extraData: Data

    /// Bytes one decoded PCM frame (one sample across all channels) occupies.
    /// This is the divisor xwma.c applies to the last `dpds` entry to get a
    /// sample count.
    public var bytesPerDecodedFrame: Int {
        channelCount * bitsPerSample / 8
    }

    /// Nominal bit rate in bits per second.
    public var bitRate: Int {
        averageBytesPerSecond * 8
    }
}

/// A framed `.xwm` file: codec parameters, the packet-boundary table, and the
/// encoded payload. Parsing is bounds-checked throughout; malformed input
/// throws `XWMError` rather than trapping.
nonisolated public struct XWMFile: Sendable {
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

    public let codec: XWMCodecParameters
    /// `dpds` contents: entry `index` is the total number of decoded PCM bytes
    /// accumulated once packet `index` has been decoded. Empty when the file
    /// carries no `dpds` chunk.
    public let packetCumulativeDecodedBytes: [UInt32]

    private let source: Data
    /// Byte range of the `data` chunk body within `source`.
    private let payloadRange: Range<Int>

    public init(data: Data) throws {
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
    public var payload: Data {
        source.subdata(
            in: (source.startIndex + payloadRange.lowerBound)
                ..< (source.startIndex + payloadRange.upperBound)
        )
    }

    public var payloadByteCount: Int {
        payloadRange.count
    }

    /// Packets in the payload. The final packet may be short; xwma.c clamps
    /// its read to what is left, so a partial trailing packet is framed, not
    /// dropped.
    public var packetCount: Int {
        (payloadByteCount + codec.blockAlign - 1) / codec.blockAlign
    }

    /// One encoded packet, or `nil` when `index` is out of range. Streaming
    /// callers use this instead of holding `payload`.
    public func packet(at index: Int) -> Data? {
        guard index >= 0, index < packetCount else { return nil }
        let start = payloadRange.lowerBound + index * codec.blockAlign
        let end = min(start + codec.blockAlign, payloadRange.upperBound)
        return source.subdata(
            in: (source.startIndex + start) ..< (source.startIndex + end)
        )
    }

    /// Total decoded PCM bytes the container claims, from the last `dpds`
    /// entry. `nil` when the file carries no packet table.
    public var declaredDecodedByteCount: Int? {
        packetCumulativeDecodedBytes.last.map(Int.init)
    }

    /// Decoded PCM sample frames the container claims (xwma.c duration math:
    /// last `dpds` entry / (channels * bitsPerSample / 8)).
    public var declaredSampleCount: Int? {
        let bytesPerFrame = codec.bytesPerDecodedFrame
        guard bytesPerFrame > 0, let decoded = declaredDecodedByteCount else { return nil }
        return decoded / bytesPerFrame
    }

    /// Playing time in seconds from the packet table, or `nil` without one.
    public var declaredDuration: Double? {
        guard codec.sampleRate > 0, let samples = declaredSampleCount else { return nil }
        return Double(samples) / Double(codec.sampleRate)
    }

    /// Whether the packet table has one entry per payload packet. Advisory:
    /// a mismatch is reported by the sweep rather than rejected, because a
    /// file can legitimately carry no `dpds` chunk at all.
    public var isPacketTableConsistent: Bool {
        packetCumulativeDecodedBytes.isEmpty
            || packetCumulativeDecodedBytes.count == packetCount
    }
}
