// CPU decode of the face color map and tint mask layouts, and the RGBA8 writer.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsMesh
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct DDSDecoderTests {
    @Test func decodesBC1FourColorBlock() throws {
        // Red then blue end points; every texel picks index 2, two thirds red.
        var block = Data([0x00, 0xF8, 0x1F, 0x00])
        block.append(Data(repeating: 0xAA, count: 4))
        let image = try DDSDecoder.topLevel(DDSFixture.file(
            width: 4, height: 4, fourCC: "DXT1", payload: block
        ))
        #expect(image.width == 4)
        #expect(Array(image.rgba[0 ..< 4]) == [170, 0, 85, 255])
        #expect(image.rgba.count == 64)
    }

    @Test func decodesBC1ThreeColorBlackAsTransparent() throws {
        var block = Data([0x1F, 0x00, 0x00, 0xF8])
        block.append(Data(repeating: 0xFF, count: 4))
        let image = try DDSDecoder.topLevel(DDSFixture.file(
            width: 4, height: 4, fourCC: "DXT1", payload: block
        ))
        #expect(Array(image.rgba[0 ..< 4]) == [0, 0, 0, 0])
    }

    @Test func decodesBC3Alpha() throws {
        // Alpha end points 255 and 0, every index 1; color block all white.
        var block = Data([255, 0])
        block.append(Data([0x49, 0x92, 0x24, 0x49, 0x92, 0x24]))
        block.append(Data([0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0]))
        let image = try DDSDecoder.topLevel(DDSFixture.file(
            width: 4, height: 4, fourCC: "DXT5", payload: block
        ))
        #expect(Array(image.rgba[0 ..< 4]) == [255, 255, 255, 0])
    }

    @Test func decodesTwentyFourBitMasks() throws {
        let data = DDSFixture.file(
            flags: 0x100F, width: 2, height: 1, pitchOrLinearSize: 6, pixelFlags: 0x40,
            fourCC: "\0\0\0\0", rgbBitCount: 24, redMask: 0xFF0000, greenMask: 0xFF00,
            blueMask: 0xFF, payload: Data([3, 2, 1, 30, 20, 10])
        )
        let image = try DDSDecoder.topLevel(data)
        #expect(image.rgba == [1, 2, 3, 255, 10, 20, 30, 255])
    }

    @Test func shortTwentyFourBitPayloadThrows() {
        let data = DDSFixture.file(
            flags: 0x100F, width: 4, height: 4, pixelFlags: 0x40, fourCC: "\0\0\0\0",
            rgbBitCount: 24, redMask: 0xFF0000, greenMask: 0xFF00, blueMask: 0xFF,
            payload: Data(count: 5)
        )
        #expect(throws: DDSError.self) { try DDSDecoder.topLevel(data) }
    }

    @Test func encodedRGBAReadsBackWithItsMipChain() throws {
        let image = DecodedImage(width: 2, height: 2, rgba: [
            0, 0, 0, 255, 100, 100, 100, 255, 200, 200, 200, 255, 100, 100, 100, 255
        ])
        let data = DDSEncoder.rgba8888(image)
        let file = try DDSFile(data: data)
        #expect(file.format == .rgba8888)
        #expect(file.mipCount == 2)
        #expect([UInt8](file.mipData(level: 1)) == [100, 100, 100, 255])
        #expect(try DDSDecoder.topLevel(data) == image)
    }
}
