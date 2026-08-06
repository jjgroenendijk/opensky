// RIFF/WAVE framing and PCM sample access for Skyrim SE's `.wav` sound
// effects (issue #352).
//
// Music and voice ship as `.xwm`; every sound effect — footsteps included —
// ships as a plain RIFF/WAVE file, so the footstep chain resolves to a format
// the M9 engine could not play until this parser existed. There is no codec
// here: a WAVE file with `wFormatTag` 1 stores its samples uncompressed, so
// "decoding" is a widening of integers into the float samples AVFAudio wants.
//
// Format policy: 8-bit unsigned and 16-bit signed linear PCM are read, and
// every other tag and width is declined with `unsupportedFormat` rather than
// guessed at. A read-only sweep of 62 `.wav` files sampled evenly across the
// install's archives on 2026-08-04 found `wFormatTag` 1 and 16 bits per sample
// in every one, mono and stereo, at 8 kHz through 44.1 kHz — so the declined
// cases are formats vanilla does not use, and a mod that does use one is
// reported instead of played back as noise.
//
// References:
//   Microsoft "Multimedia Programming Interface and Data Specifications 1.0"
//     — RIFF framing: four-character chunk id, UInt32 little-endian size not
//     counting the header, chunk bodies padded to an even byte count; the
//     WAVE form and its `fmt `/`data` chunks.
//   Microsoft WAVEFORMATEX (mmeapi.h) for the `fmt ` field order and widths
//     https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/ns-mmeapi-waveformatex
// Layout documented in docs/formats/wav.md.

import Foundation

nonisolated enum WAVError: Error, Equatable {
    /// Structural damage: not a RIFF/WAVE form, a chunk running past the end,
    /// a missing `fmt ` or `data` chunk.
    case malformed(String)
    /// Well-formed but carrying a codec or sample width this reader declines.
    case unsupportedFormat(String)
}

nonisolated struct WAVFile {
    /// The `fmt ` members this reader uses.
    struct Format: Equatable, Sendable {
        /// `wFormatTag`. 1 is WAVE_FORMAT_PCM, the only tag read here.
        let formatTag: UInt16
        let channelCount: Int
        let sampleRate: Int
        let bitsPerSample: Int
    }

    private enum Layout {
        static let riffMagic: FourCC = "RIFF"
        static let formType: FourCC = "WAVE"
        static let formatChunk: FourCC = "fmt "
        static let dataChunk: FourCC = "data"
        /// `RIFF` + UInt32 size + form type.
        static let riffHeaderSize = 12
        /// Four-character chunk id + UInt32 chunk size.
        static let chunkHeaderSize = 8
        /// The form type and everything after it are counted by the RIFF size.
        static let minimumRIFFSize = 4
        /// PCMWAVEFORMAT: the 14 common bytes plus `wBitsPerSample`.
        static let pcmFormatSize = 16
        static let pcmTag: UInt16 = 1
    }

    let format: Format
    /// Interleaved sample frames, one `Float` per sample in [-1, 1].
    let samples: [Float]
    /// Sample frames, i.e. `samples.count / channelCount`.
    var frameCount: Int {
        format.channelCount > 0 ? samples.count / format.channelCount : 0
    }

    init(data: Data) throws {
        var reader = BinaryReader(data)
        let fileEnd = try Self.readRIFFHeader(reader: &reader, byteCount: data.count)
        var format: Format?
        var payload: Data?
        while reader.offset + Layout.chunkHeaderSize <= fileEnd {
            let identifier = try reader.readFourCC()
            let size = try Int(reader.readUInt32())
            let body = reader.offset
            guard size >= 0, body + size <= fileEnd else {
                throw WAVError.malformed(
                    "chunk \"\(identifier)\" at \(body - Layout.chunkHeaderSize) claims "
                        + "\(size) bytes, only \(fileEnd - body) left in the RIFF form"
                )
            }
            switch identifier {
            case Layout.formatChunk:
                format = try Self.readFormat(reader: &reader, size: size)
            case Layout.dataChunk:
                payload = try reader.read(count: size)
            default:
                // `fact`, `LIST`, `cue ` and friends carry nothing this reader
                // needs; skipping an unknown chunk is what makes the walk
                // survive authoring tools that add their own.
                break
            }
            // Seek rather than continue from wherever the chunk reader stopped:
            // a `fmt ` chunk longer than the 16 bytes read above is normal, and
            // RIFF pads odd-sized bodies to an even boundary.
            reader.seek(to: body + size + (size % 2))
        }
        guard let format else {
            throw WAVError.malformed("no \"fmt \" chunk")
        }
        guard let payload else {
            throw WAVError.malformed("no \"data\" chunk")
        }
        self.format = format
        samples = try Self.decode(payload: payload, format: format)
    }

    private static func readRIFFHeader(
        reader: inout BinaryReader,
        byteCount: Int
    ) throws -> Int {
        guard byteCount >= Layout.riffHeaderSize else {
            throw WAVError.malformed("\(byteCount) bytes is shorter than a RIFF header")
        }
        let magic = try reader.readFourCC()
        guard magic == Layout.riffMagic else {
            throw WAVError.malformed("expected \"RIFF\", found \"\(magic)\"")
        }
        let declared = try Int(reader.readUInt32())
        let form = try reader.readFourCC()
        guard form == Layout.formType else {
            throw WAVError.malformed("expected form \"WAVE\", found \"\(form)\"")
        }
        guard declared >= Layout.minimumRIFFSize else {
            throw WAVError.malformed("RIFF size \(declared) cannot hold a form type")
        }
        // A RIFF size longer than the buffer is a truncated file; clamping to
        // the buffer keeps the walk in bounds and lets whatever chunks did
        // arrive be read.
        return min(byteCount, Layout.riffHeaderSize - Layout.minimumRIFFSize + declared)
    }

    private static func readFormat(reader: inout BinaryReader, size: Int) throws -> Format {
        guard size >= Layout.pcmFormatSize else {
            throw WAVError.malformed("\"fmt \" chunk is \(size) bytes, expected at least 16")
        }
        let formatTag = try reader.readUInt16()
        let channelCount = try Int(reader.readUInt16())
        let sampleRate = try Int(reader.readUInt32())
        _ = try reader.readUInt32() // nAvgBytesPerSec, derivable and unused
        _ = try reader.readUInt16() // nBlockAlign, derived from channels x width
        let bitsPerSample = try Int(reader.readUInt16())
        guard formatTag == Layout.pcmTag else {
            throw WAVError.unsupportedFormat(
                "wFormatTag 0x\(String(formatTag, radix: 16)) is not linear PCM"
            )
        }
        guard bitsPerSample == 8 || bitsPerSample == 16 else {
            throw WAVError.unsupportedFormat("\(bitsPerSample)-bit PCM")
        }
        guard channelCount > 0, sampleRate > 0 else {
            throw WAVError.malformed(
                "\(channelCount) channels at \(sampleRate) Hz"
            )
        }
        return Format(
            formatTag: formatTag,
            channelCount: channelCount,
            sampleRate: sampleRate,
            bitsPerSample: bitsPerSample
        )
    }

    /// Widens the stored integers to normalized floats. 8-bit PCM is unsigned
    /// with 128 as silence and 16-bit PCM is two's-complement signed with 0 as
    /// silence, which is the WAVE specification's rule and the one place the
    /// two widths differ beyond their size.
    private static func decode(payload: Data, format: Format) throws -> [Float] {
        let bytesPerSample = format.bitsPerSample / 8
        let count = payload.count / bytesPerSample
        guard count > 0 else { return [] }
        var samples = [Float](repeating: 0, count: count)
        var reader = BinaryReader(payload)
        for index in 0 ..< count {
            if bytesPerSample == 1 {
                let raw = try reader.readUInt8()
                samples[index] = (Float(raw) - 128) / 128
            } else {
                let raw = try Int16(bitPattern: reader.readUInt16())
                samples[index] = Float(raw) / 32768
            }
        }
        return samples
    }
}
