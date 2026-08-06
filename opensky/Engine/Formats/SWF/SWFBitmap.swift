// SWF bitmap character decoding, shared output type, and the
// DefineBitsLossless / DefineBitsLossless2 (zlib) formats. The JPEG-family
// tags live in SWFBitmapJPEG.swift.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 8
// "Bitmaps" — DefineBitsLossless (pp. 139-141: COLORMAPDATA, BITMAPDATA,
// PIX15, PIX24) and DefineBitsLossless2 (pp. 142-143: ALPHACOLORMAPDATA,
// ALPHABITMAPDATA). Row widths in colormapped and PIX15 pixel data are padded
// to 32-bit boundaries; PIX24 and ARGB are 4 bytes per pixel already.

import Foundation

nonisolated enum SWFBitmapError: Error, Equatable {
    /// Tag code is not one of the six bitmap definition tags.
    case unsupportedTag(UInt16)
    /// BitmapFormat byte outside the values the tag defines (3/4/5 for
    /// DefineBitsLossless, 3/5 for DefineBitsLossless2).
    case invalidLosslessFormat(tagCode: UInt16, format: UInt8)
    /// Zero or absurd dimensions (sanity cap against malformed headers).
    case invalidDimensions(width: Int, height: Int)
    /// ImageIO could not decode the embedded JPEG/PNG/GIF payload.
    case undecodableImage
    /// JPEG3/4 alpha plane does not decompress to width * height bytes.
    case alphaSizeMismatch(expected: Int, actual: Int)
}

/// A decoded bitmap character: RGBA8 pixels, row-major, 4 bytes per pixel.
/// `premultipliedAlpha` reports the source convention: DefineBitsLossless2
/// ARGB data "must already be multiplied by the alpha channel value" (spec
/// p. 143) and stays that way here; JPEG color with a separate alpha plane is
/// straight (non-premultiplied).
nonisolated struct SWFBitmap: Equatable {
    enum SourceFormat: String, Equatable {
        case lossless8
        case lossless15
        case lossless24
        case lossless32
        case jpeg
        case png
        case gif
    }

    let characterId: UInt16
    let width: Int
    let height: Int
    let pixels: Data
    let premultipliedAlpha: Bool
    let sourceFormat: SourceFormat
    /// DefineBitsJPEG4 deblocking-filter strength (8.8 fixed point, 0-100%).
    /// Decoded for completeness; no deblocking filter is applied.
    let jpegDeblockParam: Float?
}

nonisolated enum SWFBitmapDecoder {
    /// DefineBits (6), DefineBitsLossless (20), DefineBitsJPEG2 (21),
    /// DefineBitsJPEG3 (35), DefineBitsLossless2 (36), DefineBitsJPEG4 (90).
    static let tagCodes: Set<UInt16> = [6, 20, 21, 35, 36, 90]
    /// JPEGTables (8): shared encoding tables for every DefineBits tag.
    static let jpegTablesTagCode: UInt16 = 8

    /// Pixel-count sanity cap (16 megapixels) so malformed dimensions cannot
    /// balloon memory before zlib size validation kicks in.
    static let maxPixelCount = 1 << 24

    /// Decodes any bitmap definition tag. `jpegTables` is the body of the
    /// movie's JPEGTables tag, required context for DefineBits (6) only.
    static func decode(tag: SWFTag, jpegTables: Data? = nil) throws -> SWFBitmap {
        switch tag.code {
        case 20, 36:
            return try decodeLossless(tag)
        case 6, 21, 35, 90:
            return try decodeJPEGFamily(tag, jpegTables: jpegTables)
        default:
            throw SWFBitmapError.unsupportedTag(tag.code)
        }
    }

    /// Header fields shared by both lossless tags.
    struct LosslessHeader {
        let characterId: UInt16
        let width: Int
        let height: Int
    }

    static func decodeLossless(_ tag: SWFTag) throws -> SWFBitmap {
        var reader = BinaryReader(tag.body)
        let characterId = try reader.readUInt16()
        let format = try reader.readUInt8()
        let width = try Int(reader.readUInt16())
        let height = try Int(reader.readUInt16())
        guard width > 0, height > 0, width * height <= maxPixelCount else {
            throw SWFBitmapError.invalidDimensions(width: width, height: height)
        }
        let header = LosslessHeader(characterId: characterId, width: width, height: height)
        let hasAlpha = tag.code == 36
        switch format {
        case 3:
            return try decodeColormapped(&reader, header: header, rgbaTable: hasAlpha)
        case 4 where !hasAlpha:
            return try decodePix15(&reader, header: header)
        case 5:
            return hasAlpha
                ? try decodeARGB(&reader, header: header)
                : try decodePix24(&reader, header: header)
        default:
            throw SWFBitmapError.invalidLosslessFormat(tagCode: tag.code, format: format)
        }
    }

    /// COLORMAPDATA / ALPHACOLORMAPDATA: color table then 8-bit indices, rows
    /// padded to 32 bits. The spec states the premultiply rule only for ARGB
    /// ALPHABITMAPDATA, so RGBA table entries pass through unchanged
    /// (premultipliedAlpha = false; see docs/formats/swf.md).
    private static func decodeColormapped(
        _ reader: inout BinaryReader,
        header: LosslessHeader,
        rgbaTable: Bool
    ) throws -> SWFBitmap {
        let tableCount = try Int(reader.readUInt8()) + 1
        let entrySize = rgbaTable ? 4 : 3
        let stride = paddedRowBytes(header.width)
        let expected = tableCount * entrySize + stride * header.height
        let payload = try decompressRest(&reader, decompressedSize: expected)
        var table = [UInt8](repeating: 0, count: tableCount * 4)
        for entry in 0 ..< tableCount {
            let src = entry * entrySize
            table[entry * 4] = payload[src]
            table[entry * 4 + 1] = payload[src + 1]
            table[entry * 4 + 2] = payload[src + 2]
            table[entry * 4 + 3] = rgbaTable ? payload[src + 3] : 255
        }
        var pixels = [UInt8](repeating: 0, count: header.width * header.height * 4)
        let pixelBase = tableCount * entrySize
        for row in 0 ..< header.height {
            for column in 0 ..< header.width {
                let index = Int(payload[pixelBase + row * stride + column])
                let dst = (row * header.width + column) * 4
                // Out-of-range indices are malformed; render transparent
                // black instead of trapping.
                guard index < tableCount else { continue }
                pixels[dst] = table[index * 4]
                pixels[dst + 1] = table[index * 4 + 1]
                pixels[dst + 2] = table[index * 4 + 2]
                pixels[dst + 3] = table[index * 4 + 3]
            }
        }
        return SWFBitmap(
            characterId: header.characterId,
            width: header.width,
            height: header.height,
            pixels: Data(pixels),
            premultipliedAlpha: false,
            sourceFormat: .lossless8,
            jpegDeblockParam: nil
        )
    }

    /// PIX15: 1 reserved bit + 5/5/5 RGB, bit fields MSB-first (so each pixel
    /// reads as a big-endian 16-bit word), rows padded to 32 bits.
    private static func decodePix15(
        _ reader: inout BinaryReader,
        header: LosslessHeader
    ) throws -> SWFBitmap {
        let stride = paddedRowBytes(header.width * 2)
        let expected = stride * header.height
        let payload = try decompressRest(&reader, decompressedSize: expected)
        var pixels = [UInt8](repeating: 0, count: header.width * header.height * 4)
        for row in 0 ..< header.height {
            for column in 0 ..< header.width {
                let src = row * stride + column * 2
                let word = UInt16(payload[src]) << 8 | UInt16(payload[src + 1])
                let dst = (row * header.width + column) * 4
                pixels[dst] = expand5(UInt8((word >> 10) & 0x1F))
                pixels[dst + 1] = expand5(UInt8((word >> 5) & 0x1F))
                pixels[dst + 2] = expand5(UInt8(word & 0x1F))
                pixels[dst + 3] = 255
            }
        }
        return SWFBitmap(
            characterId: header.characterId,
            width: header.width,
            height: header.height,
            pixels: Data(pixels),
            premultipliedAlpha: false,
            sourceFormat: .lossless15,
            jpegDeblockParam: nil
        )
    }

    /// PIX24: reserved byte + RGB, four bytes per pixel (inherently 32-bit
    /// aligned).
    private static func decodePix24(
        _ reader: inout BinaryReader,
        header: LosslessHeader
    ) throws -> SWFBitmap {
        let count = header.width * header.height
        let payload = try decompressRest(&reader, decompressedSize: count * 4)
        var pixels = [UInt8](repeating: 0, count: count * 4)
        for pixel in 0 ..< count {
            pixels[pixel * 4] = payload[pixel * 4 + 1]
            pixels[pixel * 4 + 1] = payload[pixel * 4 + 2]
            pixels[pixel * 4 + 2] = payload[pixel * 4 + 3]
            pixels[pixel * 4 + 3] = 255
        }
        return SWFBitmap(
            characterId: header.characterId,
            width: header.width,
            height: header.height,
            pixels: Data(pixels),
            premultipliedAlpha: false,
            sourceFormat: .lossless24,
            jpegDeblockParam: nil
        )
    }

    /// ALPHABITMAPDATA: ARGB per pixel; "the RGB data must already be
    /// multiplied by the alpha channel value" (spec p. 143).
    private static func decodeARGB(
        _ reader: inout BinaryReader,
        header: LosslessHeader
    ) throws -> SWFBitmap {
        let count = header.width * header.height
        let payload = try decompressRest(&reader, decompressedSize: count * 4)
        var pixels = [UInt8](repeating: 0, count: count * 4)
        for pixel in 0 ..< count {
            pixels[pixel * 4] = payload[pixel * 4 + 1]
            pixels[pixel * 4 + 1] = payload[pixel * 4 + 2]
            pixels[pixel * 4 + 2] = payload[pixel * 4 + 3]
            pixels[pixel * 4 + 3] = payload[pixel * 4]
        }
        return SWFBitmap(
            characterId: header.characterId,
            width: header.width,
            height: header.height,
            pixels: Data(pixels),
            premultipliedAlpha: true,
            sourceFormat: .lossless32,
            jpegDeblockParam: nil
        )
    }

    /// Rows pad to the next 32-bit boundary (spec note, p. 140).
    private static func paddedRowBytes(_ bytes: Int) -> Int {
        (bytes + 3) & ~3
    }

    private static func decompressRest(
        _ reader: inout BinaryReader,
        decompressedSize: Int
    ) throws -> [UInt8] {
        let stream = try reader.read(count: reader.bytesRemaining)
        return try [UInt8](Zlib.decompress(stream, decompressedSize: decompressedSize))
    }

    /// Linear 5-bit to 8-bit channel expansion (top bits replicated).
    private static func expand5(_ value: UInt8) -> UInt8 {
        value << 3 | value >> 2
    }
}
