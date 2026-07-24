// Unit tests for SWF bitmap tag decoding. Lossless fixtures are byte-built
// zlib payloads; JPEG/PNG payloads are generated in code through ImageIO —
// all synthetic, never extracted game files.

import CoreGraphics
import Foundation
import ImageIO
@testable import opensky
import Testing
import UniformTypeIdentifiers

struct SWFBitmapTests {
    // MARK: - Fixture helpers

    /// DefineBitsLossless/2 tag body: header + zlib-compressed payload.
    private func losslessBody(
        characterId: UInt16,
        format: UInt8,
        size: (UInt16, UInt16),
        colorTableSize: UInt8?,
        payload: [UInt8]
    ) -> Data {
        var body = Data()
        body.appendUInt16(characterId)
        body.append(format)
        body.appendUInt16(size.0)
        body.appendUInt16(size.1)
        if let colorTableSize {
            body.append(colorTableSize)
        }
        body.append(ESMFixture.zlibStream(Data(payload)))
        return body
    }

    /// Renders a solid-color image and encodes it via ImageIO.
    private func encodedImage(type: UTType, rgba: [UInt8]) -> Data {
        let width = 4
        let height = 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0 ..< width * height {
            pixels[pixel * 4] = rgba[0]
            pixels[pixel * 4 + 1] = rgba[1]
            pixels[pixel * 4 + 2] = rgba[2]
            pixels[pixel * 4 + 3] = rgba[3]
        }
        let data = CFDataCreateMutable(nil, 0)
        // makeImage() copies the bitmap, so the context (and its pointer into
        // `pixels`) must not escape the closure.
        let madeImage: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            return context?.makeImage()
        }
        guard
            let data,
            let image = madeImage,
            let destination = CGImageDestinationCreateWithData(
                data,
                type.identifier as CFString,
                1,
                nil
            )
        else {
            Issue.record("could not build synthetic \(type.identifier) image")
            return Data()
        }
        // Max quality keeps the JPEG round-trip close to the source color.
        let options = [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    // MARK: - Lossless

    @Test func decodesColormappedLossless() throws {
        // 3x2, two-entry RGB table, rows padded from 3 to 4 bytes.
        let payload: [UInt8] = [
            255, 0, 0, 0, 255, 0, // table: red, green
            0, 1, 0, 0, // row 0 + pad
            1, 0, 1, 0 // row 1 + pad
        ]
        let body = losslessBody(
            characterId: 5,
            format: 3,
            size: (3, 2),
            colorTableSize: 1, // stored count-minus-one
            payload: payload
        )
        let bitmap = try SWFBitmapDecoder.decode(tag: SWFTag(code: 20, body: body))
        #expect(bitmap.characterId == 5)
        #expect(bitmap.width == 3)
        #expect(bitmap.height == 2)
        #expect(bitmap.sourceFormat == .lossless8)
        #expect(!bitmap.premultipliedAlpha)
        #expect(bitmap.pixels == Data([
            255, 0, 0, 255, 0, 255, 0, 255, 255, 0, 0, 255,
            0, 255, 0, 255, 255, 0, 0, 255, 0, 255, 0, 255
        ]))
    }

    @Test func decodesPix15Lossless() throws {
        // 1x1, PIX15 0x7C1F = 0 11111 00000 11111 -> magenta; row pads to 4.
        let body = losslessBody(
            characterId: 6,
            format: 4,
            size: (1, 1),
            colorTableSize: nil,
            payload: [0x7C, 0x1F, 0, 0]
        )
        let bitmap = try SWFBitmapDecoder.decode(tag: SWFTag(code: 20, body: body))
        #expect(bitmap.sourceFormat == .lossless15)
        #expect(bitmap.pixels == Data([255, 0, 255, 255]))
    }

    @Test func decodesPix24Lossless() throws {
        // 2x1 PIX24: reserved byte then RGB.
        let body = losslessBody(
            characterId: 7,
            format: 5,
            size: (2, 1),
            colorTableSize: nil,
            payload: [0, 10, 20, 30, 0, 40, 50, 60]
        )
        let bitmap = try SWFBitmapDecoder.decode(tag: SWFTag(code: 20, body: body))
        #expect(bitmap.sourceFormat == .lossless24)
        #expect(bitmap.pixels == Data([10, 20, 30, 255, 40, 50, 60, 255]))
    }

    @Test func decodesLossless2ARGBAsPremultiplied() throws {
        // 1x2 ARGB: half-transparent premultiplied red, opaque blue.
        let body = losslessBody(
            characterId: 8,
            format: 5,
            size: (1, 2),
            colorTableSize: nil,
            payload: [128, 128, 0, 0, 255, 0, 0, 255]
        )
        let bitmap = try SWFBitmapDecoder.decode(tag: SWFTag(code: 36, body: body))
        #expect(bitmap.sourceFormat == .lossless32)
        #expect(bitmap.premultipliedAlpha)
        #expect(bitmap.pixels == Data([128, 0, 0, 128, 0, 0, 255, 255]))
    }

    @Test func decodesLossless2ColormappedWithAlphaTable() throws {
        // 1x1, single RGBA table entry with alpha 64.
        let body = losslessBody(
            characterId: 9,
            format: 3,
            size: (1, 1),
            colorTableSize: 0,
            payload: [200, 100, 50, 64, 0, 0, 0, 0]
        )
        let bitmap = try SWFBitmapDecoder.decode(tag: SWFTag(code: 36, body: body))
        #expect(bitmap.sourceFormat == .lossless8)
        #expect(bitmap.pixels == Data([200, 100, 50, 64]))
    }

    @Test func rejectsBadLosslessFormatAndDimensions() {
        let badFormat = losslessBody(
            characterId: 1,
            format: 4, // 15-bit is not defined for Lossless2
            size: (1, 1),
            colorTableSize: nil,
            payload: [0, 0, 0, 0]
        )
        #expect(throws: SWFBitmapError.invalidLosslessFormat(tagCode: 36, format: 4)) {
            _ = try SWFBitmapDecoder.decode(tag: SWFTag(code: 36, body: badFormat))
        }
        let zeroSize = losslessBody(
            characterId: 1,
            format: 5,
            size: (0, 4),
            colorTableSize: nil,
            payload: []
        )
        #expect(throws: SWFBitmapError.invalidDimensions(width: 0, height: 4)) {
            _ = try SWFBitmapDecoder.decode(tag: SWFTag(code: 20, body: zeroSize))
        }
    }

    // MARK: - JPEG family

    @Test func decodesDefineBitsJPEG2() throws {
        let jpeg = encodedImage(type: .jpeg, rgba: [200, 40, 40, 255])
        var body = Data()
        body.appendUInt16(21)
        body.append(jpeg)
        let bitmap = try SWFBitmapDecoder.decode(tag: SWFTag(code: 21, body: body))
        #expect(bitmap.characterId == 21)
        #expect(bitmap.sourceFormat == .jpeg)
        #expect(bitmap.width == 4)
        #expect(bitmap.height == 2)
        // JPEG is lossy; the solid color survives within a small delta.
        #expect(abs(Int(bitmap.pixels[0]) - 200) < 12)
        #expect(bitmap.pixels[3] == 255)
    }

    @Test func decodesDefineBitsWithSeparateJPEGTables() throws {
        let jpeg = encodedImage(type: .jpeg, rgba: [10, 220, 10, 255])
        // Minimal JPEGTables stream: just SOI + EOI; the merge keeps the
        // tables' SOI and drops the scan's.
        let tables = Data([0xFF, 0xD8, 0xFF, 0xD9])
        var body = Data()
        body.appendUInt16(2)
        body.append(jpeg)
        let bitmap = try SWFBitmapDecoder.decode(
            tag: SWFTag(code: 6, body: body),
            jpegTables: tables
        )
        #expect(bitmap.characterId == 2)
        #expect(bitmap.width == 4)
        #expect(abs(Int(bitmap.pixels[1]) - 220) < 12)
    }

    @Test func decodesJPEG3AlphaPlane() throws {
        let jpeg = encodedImage(type: .jpeg, rgba: [120, 120, 120, 255])
        let alphaPlane = ESMFixture.zlibStream(Data(repeating: 99, count: 4 * 2))
        var body = Data()
        body.appendUInt16(35)
        body.appendUInt32(UInt32(jpeg.count))
        body.append(jpeg)
        body.append(alphaPlane)
        let bitmap = try SWFBitmapDecoder.decode(tag: SWFTag(code: 35, body: body))
        #expect(bitmap.sourceFormat == .jpeg)
        #expect(!bitmap.premultipliedAlpha)
        #expect(bitmap.pixels[3] == 99)
        #expect(bitmap.pixels[7] == 99)
    }

    @Test func decodesJPEG4DeblockParam() throws {
        let jpeg = encodedImage(type: .jpeg, rgba: [50, 50, 200, 255])
        let alphaPlane = ESMFixture.zlibStream(Data(repeating: 255, count: 4 * 2))
        var body = Data()
        body.appendUInt16(90)
        body.appendUInt32(UInt32(jpeg.count))
        body.appendUInt16(0x0180) // 1.5 in 8.8 fixed point
        body.append(jpeg)
        body.append(alphaPlane)
        let bitmap = try SWFBitmapDecoder.decode(tag: SWFTag(code: 90, body: body))
        #expect(bitmap.jpegDeblockParam == 1.5)
    }

    @Test func detectsPNGPayloadBySignature() throws {
        let png = encodedImage(type: .png, rgba: [1, 2, 3, 255])
        var body = Data()
        body.appendUInt16(30)
        body.append(png)
        let bitmap = try SWFBitmapDecoder.decode(tag: SWFTag(code: 21, body: body))
        #expect(bitmap.sourceFormat == .png)
        // PNG is lossless: exact pixels.
        #expect(bitmap.pixels.prefix(4) == Data([1, 2, 3, 255]))
    }

    @Test func stripsErroneousPreSWF8JPEGHeader() throws {
        let jpeg = encodedImage(type: .jpeg, rgba: [90, 90, 90, 255])
        var body = Data()
        body.appendUInt16(11)
        body.append(Data([0xFF, 0xD9, 0xFF, 0xD8])) // erroneous prefix
        body.append(jpeg)
        let bitmap = try SWFBitmapDecoder.decode(tag: SWFTag(code: 21, body: body))
        #expect(bitmap.width == 4)
        #expect(bitmap.height == 2)
    }

    @Test func rejectsAlphaPlaneSizeMismatch() throws {
        let jpeg = encodedImage(type: .jpeg, rgba: [0, 0, 0, 255])
        let shortPlane = ESMFixture.zlibStream(Data(repeating: 1, count: 3))
        var body = Data()
        body.appendUInt16(1)
        body.appendUInt32(UInt32(jpeg.count))
        body.append(jpeg)
        body.append(shortPlane)
        #expect(throws: SWFBitmapError.self) {
            _ = try SWFBitmapDecoder.decode(tag: SWFTag(code: 35, body: body))
        }
    }

    @Test func rejectsGarbagePayloadWithTypedError() {
        var body = Data()
        body.appendUInt16(1)
        body.append(Data([0x00, 0x01, 0x02, 0x03]))
        #expect(throws: SWFBitmapError.undecodableImage) {
            _ = try SWFBitmapDecoder.decode(tag: SWFTag(code: 21, body: body))
        }
        #expect(throws: SWFBitmapError.unsupportedTag(99)) {
            _ = try SWFBitmapDecoder.decode(tag: SWFTag(code: 99, body: Data()))
        }
    }
}
