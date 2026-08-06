// SWF container decoder: signature/compression, header fields, and the flat
// tag stream. Shapes, fonts, and the display list are decoded in later
// milestones (8.2.2-8.2.4); this stage only frames the container.
//
// Reference: Adobe SWF File Format Specification, version 19, "The SWF header"
// and "The tag format". Layout documented in docs/formats/swf.md.
//
// Skyrim's UI files are authored for Scaleform GFx, which reuses the Adobe
// container framing but adds extension tags (see SWFTagName). Those tags parse
// as opaque bodies here and are reported as "unknown".

import Foundation

nonisolated enum SWFError: Error, Equatable {
    /// Signature is not one of the three SWF magics.
    case notASWF
    /// ZWS (LZMA) body compression — recognized but not decoded at this stage.
    case unsupportedCompression(signature: String)
    /// FileLength field is smaller than the mandatory 8-byte header.
    case invalidFileLength(Int)
}

/// One framed tag: its record-header code and the raw body bytes. The body is
/// left undecoded — later milestones interpret it by code.
nonisolated struct SWFTag: Equatable {
    let code: UInt16
    let body: Data
}

/// Rectangle in twips (1/20 px), as stored in the FrameSize RECT.
nonisolated struct SWFRect: Equatable {
    let xMin: Int32
    let xMax: Int32
    let yMin: Int32
    let yMax: Int32
}

/// A parsed SWF container: header fields plus the flat tag sequence, ending
/// with the End tag (code 0). Trailing bytes after End are ignored.
nonisolated struct SWFFile {
    enum Compression: Equatable {
        case none // FWS
        case zlib // CWS
    }

    let version: UInt8
    let compression: Compression
    /// Uncompressed length of the whole file including the 8-byte header.
    let fileLength: Int
    let frameSize: SWFRect
    let frameRate: Float
    let frameCount: UInt16
    /// Tags in stream order, terminating End tag included.
    let tags: [SWFTag]

    init(data: Data) throws {
        var reader = BinaryReader(data)
        let signatureData = try reader.read(count: 3)
        version = try reader.readUInt8()
        let length = try Int(reader.readUInt32())
        guard length >= 8 else { throw SWFError.invalidFileLength(length) }
        fileLength = length

        // Bytes past the 8-byte header form the body: raw for FWS, one zlib
        // stream (CMF/FLG + deflate + adler32) for CWS whose decompressed size
        // is FileLength - 8. ZWS (LZMA, SWF >= 13) is recognized but declined.
        guard let signature = String(bytes: signatureData, encoding: .ascii) else {
            throw SWFError.notASWF
        }
        let rest = try reader.read(count: reader.bytesRemaining)
        let body: Data
        switch signature {
        case "FWS":
            compression = .none
            body = rest
        case "CWS":
            compression = .zlib
            body = try Zlib.decompress(rest, decompressedSize: length - 8)
        case "ZWS":
            throw SWFError.unsupportedCompression(signature: signature)
        default:
            throw SWFError.notASWF
        }

        let parsed = try Self.parseBody(body)
        frameSize = parsed.frameSize
        frameRate = parsed.frameRate
        frameCount = parsed.frameCount
        tags = parsed.tags
    }

    /// Header fields after the signature, plus the parsed tag stream.
    private struct ParsedBody {
        let frameSize: SWFRect
        let frameRate: Float
        let frameCount: UInt16
        let tags: [SWFTag]
    }

    private static func parseBody(_ body: Data) throws -> ParsedBody {
        // FrameSize RECT: bit-packed MSB-first. Nbits = UB[5], then Xmin, Xmax,
        // Ymin, Ymax each SB[Nbits]. Byte-align afterwards.
        var bits = SWFBitReader(body)
        let nbits = try Int(bits.readUB(5))
        let rect = try SWFRect(
            xMin: bits.readSB(nbits),
            xMax: bits.readSB(nbits),
            yMin: bits.readSB(nbits),
            yMax: bits.readSB(nbits)
        )
        bits.align()

        var reader = BinaryReader(body, offset: bits.byteOffset)
        // FrameRate: 8.8 fixed point stored as UI16 LE (value / 256).
        let rate = try Float(reader.readUInt16()) / 256
        let count = try reader.readUInt16()
        return try ParsedBody(
            frameSize: rect,
            frameRate: rate,
            frameCount: count,
            tags: parseTags(&reader)
        )
    }

    /// RECORDHEADER framing: UI16 LE, code = value >> 6, length = value & 0x3F.
    /// length == 0x3F means the real length follows as a UI32 LE ("long" tag).
    /// The stream terminates at the End tag (code 0). Internal because
    /// DefineSprite (39) bodies carry the same nested tag framing (SWFMovie).
    static func parseTags(_ reader: inout BinaryReader) throws -> [SWFTag] {
        var tags: [SWFTag] = []
        while true {
            let recordHeader = try reader.readUInt16()
            let code = recordHeader >> 6
            var length = Int(recordHeader & 0x3F)
            if length == 0x3F {
                length = try Int(reader.readUInt32())
            }
            let tagBody = try reader.read(count: length)
            tags.append(SWFTag(code: code, body: tagBody))
            if code == 0 {
                break
            } // End tag
        }
        return tags
    }
}
