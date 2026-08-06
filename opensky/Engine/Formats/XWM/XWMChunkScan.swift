// RIFF chunk walk for `.xwm` (xWMA) files: validates the RIFF/XWMA header,
// then collects the `fmt `, `dpds` and `data` chunks. Satellite of
// XWMFile.swift, which owns the codec policy; this type owns the on-disk
// framing only.
//
// References:
//   Microsoft "Multimedia Programming Interface and Data Specifications 1.0"
//     — RIFF framing: four-character chunk id, UInt32 little-endian size not
//     counting the header, chunk bodies padded to an even byte count.
//   Microsoft xWMA, MultimediaWiki
//     https://wiki.multimedia.cx/index.php/Microsoft_xWMA
//   FFmpeg libavformat/xwma.c (read as documentation, not transcribed)
//     https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/xwma.c
// Layout documented in docs/formats/xwm.md.

import Foundation

/// The three chunks OpenSky reads, located inside one `.xwm` buffer.
nonisolated struct XWMChunkScan {
    /// `fmt ` fields exactly as stored, before any range validation.
    struct RawFormat: Equatable {
        let formatTag: UInt16
        let channelCount: Int
        let sampleRate: Int
        let averageBytesPerSecond: Int
        let blockAlign: Int
        let bitsPerSample: Int
        let extraData: Data
    }

    private enum Layout {
        static let riffMagic: FourCC = "RIFF"
        static let formType: FourCC = "XWMA"
        static let formatChunk: FourCC = "fmt "
        static let packetTableChunk: FourCC = "dpds"
        static let dataChunk: FourCC = "data"
        /// `RIFF` + UInt32 size + form type.
        static let riffHeaderSize = 12
        /// Four-character chunk id + UInt32 chunk size.
        static let chunkHeaderSize = 8
        /// The form type and everything after it are counted by the RIFF size.
        static let minimumRIFFSize = 4
        /// WAVEFORMATEX: 16 bytes of PCMWAVEFORMAT plus the `cbSize` field.
        /// MultimediaWiki records xWMA's `fmt ` chunk as 18 bytes.
        static let waveFormatExSize = 18
        /// `dpds` elements are 32-bit little-endian integers.
        static let packetTableEntrySize = 4
    }

    let format: RawFormat
    let packetTable: [UInt32]
    let payloadRange: Range<Int>

    init(data: Data) throws {
        var reader = BinaryReader(data)
        let fileEnd = try Self.readRIFFHeader(reader: &reader, byteCount: data.count)

        var scanned = Accumulator()
        while reader.offset + Layout.chunkHeaderSize <= fileEnd {
            let identifier = try reader.readFourCC()
            let size = try Int(reader.readUInt32())
            let body = reader.offset
            guard body + size <= fileEnd else {
                throw XWMError.malformed(
                    "chunk \"\(identifier)\" at \(body - Layout.chunkHeaderSize) claims "
                        + "\(size) bytes, only \(fileEnd - body) left in the RIFF form"
                )
            }
            try Self.record(
                identifier: identifier,
                body: body ..< (body + size),
                reader: &reader,
                into: &scanned
            )
            // RIFF pads odd-length chunk bodies to an even boundary; the pad
            // byte is not counted by the size field.
            reader.seek(to: body + size + (size % 2))
        }

        guard let scannedFormat = scanned.format else {
            throw XWMError.malformed("missing required \"fmt \" chunk")
        }
        guard let scannedPayload = scanned.payload else {
            throw XWMError.malformed("missing required \"data\" chunk")
        }
        guard !scannedPayload.isEmpty else {
            throw XWMError.malformed("\"data\" chunk is empty")
        }
        format = scannedFormat
        packetTable = scanned.table ?? []
        payloadRange = scannedPayload
    }

    /// Chunks found so far. `nil` distinguishes "absent" from "present but
    /// empty", which the duplicate-chunk checks depend on.
    private struct Accumulator {
        var format: RawFormat?
        var table: [UInt32]?
        var payload: Range<Int>?
    }

    /// Dispatches one chunk body. Unknown chunk ids are skipped, as RIFF
    /// requires; the caller advances the cursor past every body regardless.
    private static func record(
        identifier: FourCC,
        body: Range<Int>,
        reader: inout BinaryReader,
        into scanned: inout Accumulator
    ) throws {
        switch identifier {
        case Layout.formatChunk:
            guard scanned.format == nil else {
                throw XWMError.malformed("duplicate \"fmt \" chunk")
            }
            scanned.format = try readFormat(reader: &reader, size: body.count)
        case Layout.packetTableChunk:
            // xwma.c rejects a second dpds chunk outright; so does OpenSky,
            // because the two tables cannot both index the payload.
            guard scanned.table == nil else {
                throw XWMError.malformed("duplicate \"dpds\" chunk")
            }
            scanned.table = try readPacketTable(reader: &reader, size: body.count)
        case Layout.dataChunk:
            guard scanned.payload == nil else {
                throw XWMError.malformed("duplicate \"data\" chunk")
            }
            scanned.payload = body
        default:
            break
        }
    }

    /// `RIFF` + UInt32 size + `XWMA`. Returns the end offset of the form.
    private static func readRIFFHeader(
        reader: inout BinaryReader,
        byteCount: Int
    ) throws -> Int {
        guard byteCount >= Layout.riffHeaderSize else {
            throw XWMError.malformed(
                "file is \(byteCount) bytes, shorter than the 12-byte RIFF header"
            )
        }
        guard try reader.readFourCC() == Layout.riffMagic else {
            throw XWMError.malformed("bad magic (expected \"RIFF\")")
        }
        let riffSize = try Int(reader.readUInt32())
        guard try reader.readFourCC() == Layout.formType else {
            throw XWMError.malformed("RIFF form type is not \"XWMA\"")
        }
        guard riffSize >= Layout.minimumRIFFSize else {
            throw XWMError.malformed("RIFF size \(riffSize) is smaller than the form type")
        }
        let fileEnd = Layout.chunkHeaderSize + riffSize
        guard fileEnd <= byteCount else {
            throw XWMError.malformed(
                "RIFF size \(riffSize) runs past the end of a \(byteCount)-byte file"
            )
        }
        return fileEnd
    }

    /// WAVEFORMATEX in `fmt `: `wFormatTag`, `nChannels`, `nSamplesPerSec`,
    /// `nAvgBytesPerSec`, `nBlockAlign`, `wBitsPerSample`, `cbSize`
    /// (Microsoft mmeapi.h), followed by `cbSize` bytes of codec extradata.
    private static func readFormat(
        reader: inout BinaryReader,
        size: Int
    ) throws -> RawFormat {
        guard size >= Layout.waveFormatExSize else {
            throw XWMError.malformed(
                "\"fmt \" chunk is \(size) bytes, expected at least "
                    + "\(Layout.waveFormatExSize) (WAVEFORMATEX)"
            )
        }
        let formatTag = try reader.readUInt16()
        let channelCount = try Int(reader.readUInt16())
        let sampleRate = try Int(reader.readUInt32())
        let averageBytesPerSecond = try Int(reader.readUInt32())
        let blockAlign = try Int(reader.readUInt16())
        let bitsPerSample = try Int(reader.readUInt16())
        let extraSize = try Int(reader.readUInt16())
        let available = size - Layout.waveFormatExSize
        guard extraSize <= available else {
            throw XWMError.malformed(
                "\"fmt \" cbSize \(extraSize) exceeds the \(available) bytes left in the chunk"
            )
        }
        return try RawFormat(
            formatTag: formatTag,
            channelCount: channelCount,
            sampleRate: sampleRate,
            averageBytesPerSecond: averageBytesPerSecond,
            blockAlign: blockAlign,
            bitsPerSample: bitsPerSample,
            extraData: reader.read(count: extraSize)
        )
    }

    /// `dpds`: a run of UInt32 little-endian cumulative decoded byte counts,
    /// one per encoded packet (MultimediaWiki; xwma.c reads size / 4 entries).
    private static func readPacketTable(
        reader: inout BinaryReader,
        size: Int
    ) throws -> [UInt32] {
        guard size % Layout.packetTableEntrySize == 0 else {
            throw XWMError.malformed(
                "\"dpds\" chunk size \(size) is not a multiple of 4"
            )
        }
        var entries: [UInt32] = []
        entries.reserveCapacity(size / Layout.packetTableEntrySize)
        for _ in 0 ..< (size / Layout.packetTableEntrySize) {
            try entries.append(reader.readUInt32())
        }
        return entries
    }
}
