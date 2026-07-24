// JPEG-family bitmap tags: DefineBits (6) + JPEGTables (8), DefineBitsJPEG2
// (21), DefineBitsJPEG3 (35), DefineBitsJPEG4 (90). Payload decoding goes
// through ImageIO/CoreGraphics (Apple frameworks — no third-party codec).
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 8
// "Bitmaps", pp. 137-139 and 143. Spec quirks handled here:
// - Before SWF 8, JPEG data could carry an erroneous 0xFF 0xD9 0xFF 0xD8
//   header before the real SOI marker; it is stripped.
// - DefineBits holds only the image scan; the movie-wide JPEGTables tag holds
//   the encoding tables. Both begin with SOI and end with EOI, so the full
//   stream is tables-without-EOI followed by image-without-SOI.
// - From SWF 8 on, DefineBitsJPEG2/3/4 ImageData may actually be PNG
//   (89 50 4E 47 0D 0A 1A 0A) or GIF89a (47 49 46 38 39 61), detected by
//   signature; the JPEG3/4 alpha plane applies to JPEG payloads only.

import CoreGraphics
import Foundation
import ImageIO

extension SWFBitmapDecoder {
    static func decodeJPEGFamily(_ tag: SWFTag, jpegTables: Data?) throws -> SWFBitmap {
        var reader = BinaryReader(tag.body)
        let characterId = try reader.readUInt16()
        var alphaPlane: Data?
        var deblockParam: Float?
        let imageData: Data
        switch tag.code {
        case 6:
            let scan = try reader.read(count: reader.bytesRemaining)
            imageData = mergedJPEG(tables: jpegTables, body: scan)
        case 21:
            imageData = try strippingErroneousJPEGHeader(reader.read(count: reader.bytesRemaining))
        default: // 35, 90 — AlphaDataOffset counts the ImageData bytes.
            let alphaOffset = try Int(reader.readUInt32())
            if tag.code == 90 {
                // DeblockParam: 8.8 fixed-point filter strength.
                deblockParam = try Float(reader.readUInt16()) / 256
            }
            imageData = try strippingErroneousJPEGHeader(reader.read(count: alphaOffset))
            alphaPlane = try reader.read(count: reader.bytesRemaining)
        }
        let format = detectImageFormat(imageData)
        let decoded = try renderRGBA(imageData)
        var pixels = decoded.pixels
        var premultiplied = format != .jpeg
        if let alphaPlane, !alphaPlane.isEmpty, format == .jpeg {
            try applyAlphaPlane(alphaPlane, to: &pixels, decoded: decoded)
            premultiplied = false
        }
        return SWFBitmap(
            characterId: characterId,
            width: decoded.width,
            height: decoded.height,
            pixels: Data(pixels),
            premultipliedAlpha: premultiplied,
            sourceFormat: format,
            jpegDeblockParam: deblockParam
        )
    }

    /// Concatenates the JPEGTables stream and a DefineBits scan into one
    /// decodable JPEG: tables lose their trailing EOI, the scan loses its
    /// leading SOI. Empty or absent tables leave the scan untouched.
    static func mergedJPEG(tables: Data?, body: Data) -> Data {
        let scan = strippingErroneousJPEGHeader(body)
        guard let tables, tables.count >= 2 else { return scan }
        var head = strippingErroneousJPEGHeader(tables)
        if head.suffix(2).elementsEqual([0xFF, 0xD9]) {
            head = head.dropLast(2)
        }
        guard !head.isEmpty else { return scan }
        var tail = scan
        if tail.prefix(2).elementsEqual([0xFF, 0xD8]) {
            tail = tail.dropFirst(2)
        }
        return head + tail
    }

    /// Drops any pre-SWF8 erroneous 0xFF 0xD9 0xFF 0xD8 prefix headers.
    static func strippingErroneousJPEGHeader(_ data: Data) -> Data {
        var out = data
        while out.count >= 4, out.prefix(4).elementsEqual([0xFF, 0xD9, 0xFF, 0xD8]) {
            out = out.dropFirst(4)
        }
        return out
    }

    /// Payload sniffing per the spec's signature lists; anything else is
    /// treated as JPEG.
    static func detectImageFormat(_ data: Data) -> SWFBitmap.SourceFormat {
        if data.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .png
        }
        if data.prefix(6).elementsEqual([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) {
            return .gif
        }
        return .jpeg
    }

    /// ImageIO decode result normalized to RGBA8.
    struct DecodedImage {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    private static func renderRGBA(_ data: Data) throws -> DecodedImage {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw SWFBitmapError.undecodableImage
        }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width * height <= maxPixelCount else {
            throw SWFBitmapError.invalidDimensions(width: width, height: height)
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    // R,G,B,A byte order in memory; CGContext requires a
                    // premultiplied alpha layout for drawing.
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw SWFBitmapError.undecodableImage }
        return DecodedImage(width: width, height: height, pixels: pixels)
    }

    /// JPEG3/4 BitmapAlphaData: one zlib-compressed alpha byte per pixel,
    /// substituted into the opaque JPEG's alpha channel.
    private static func applyAlphaPlane(
        _ plane: Data,
        to pixels: inout [UInt8],
        decoded: DecodedImage
    ) throws {
        let expected = decoded.width * decoded.height
        let alpha: Data
        do {
            alpha = try Zlib.decompress(plane, decompressedSize: expected)
        } catch let ZlibError.sizeMismatch(_, actual) {
            throw SWFBitmapError.alphaSizeMismatch(expected: expected, actual: actual)
        }
        for index in 0 ..< expected {
            pixels[index * 4 + 3] = alpha[alpha.startIndex + index]
        }
    }
}
