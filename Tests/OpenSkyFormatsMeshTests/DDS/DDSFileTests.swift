// DDS parser tests over synthetic in-code files (DDSFixture).

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsMesh
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct DDSFileTests {
    @Test func decodesBC1WithFullMipChain() throws {
        let file = try DDSFile(data: DDSFixture.file(
            format: .bc1,
            width: 8,
            height: 8,
            mipCount: 4
        ))
        #expect(file.width == 8)
        #expect(file.height == 8)
        #expect(file.mipCount == 4)
        #expect(file.format == .bc1)
        #expect(!file.declaresSRGB)
    }

    @Test func decodesXRGB8888WithFullMipChain() throws {
        let file = try DDSFile(data: DDSFixture.xrgb8888File(
            width: 8,
            height: 4,
            mipCount: 4
        ))
        #expect(file.width == 8)
        #expect(file.height == 4)
        #expect(file.mipCount == 4)
        #expect(file.format == .xrgb8888)
        #expect(!file.declaresSRGB)
        #expect((0 ..< 4).map { file.width(level: $0) } == [8, 4, 2, 1])
        #expect((0 ..< 4).map { file.height(level: $0) } == [4, 2, 1, 1])
        #expect((0 ..< 4).map { file.bytesPerRow(level: $0) } == [32, 16, 8, 4])
        #expect((0 ..< 4).map { file.mipData(level: $0).count } == [128, 32, 8, 4])
        for level in 0 ..< 4 {
            #expect(file.mipData(level: level).allSatisfy { $0 == UInt8(level) })
        }
    }

    @Test(arguments: [
        ("DXT1", DDSPixelFormat.bc1),
        ("DXT3", .bc2),
        ("DXT5", .bc3),
        ("ATI1", .bc4),
        ("BC4U", .bc4),
        ("ATI2", .bc5),
        ("BC5U", .bc5)
    ])
    func mapsLegacyFourCC(fourCC: String, expected: DDSPixelFormat) throws {
        let data = DDSFixture.file(
            width: 4,
            height: 4,
            fourCC: fourCC,
            payload: Data(count: expected.bytesPerBlock)
        )
        #expect(try DDSFile(data: data).format == expected)
    }

    @Test(arguments: [
        (UInt32(71), DDSPixelFormat.bc1, false),
        (72, .bc1, true),
        (74, .bc2, false),
        (75, .bc2, true),
        (77, .bc3, false),
        (78, .bc3, true),
        (80, .bc4, false),
        (83, .bc5, false),
        (98, .bc7, false),
        (99, .bc7, true)
    ])
    func mapsDXGIFormats(dxgi: UInt32, expected: DDSPixelFormat, srgb: Bool) throws {
        let data = DDSFixture.file(
            width: 4,
            height: 4,
            fourCC: "DX10",
            dx10: .init(dxgiFormat: dxgi),
            payload: Data(count: expected.bytesPerBlock)
        )
        let file = try DDSFile(data: data)
        #expect(file.format == expected)
        #expect(file.declaresSRGB == srgb)
    }

    /// Mip dimensions clamp at 1 and blocks round up — 16x8 tail levels.
    @Test func mipLevelMathRoundsUpAndClamps() throws {
        let file = try DDSFile(
            data: DDSFixture.file(format: .bc3, width: 16, height: 8, mipCount: 5)
        )
        #expect((0 ..< 5).map { file.width(level: $0) } == [16, 8, 4, 2, 1])
        #expect((0 ..< 5).map { file.height(level: $0) } == [8, 4, 2, 1, 1])
        // blocksWide: 4,2,1,1,1 * 16 bytes
        #expect((0 ..< 5).map { file.bytesPerRow(level: $0) } == [64, 32, 16, 16, 16])
        // level sizes: 4*2, 2*1, 1*1, 1*1, 1*1 blocks
        #expect((0 ..< 5).map { file.mipData(level: $0).count } == [128, 32, 16, 16, 16])
    }

    /// Fixture tags every byte of level N with value N.
    @Test func mipDataSlicesTheRightBytes() throws {
        let file = try DDSFile(data: DDSFixture.file(
            format: .bc7,
            width: 8,
            height: 8,
            mipCount: 4
        ))
        for level in 0 ..< 4 {
            #expect(file.mipData(level: level).allSatisfy { $0 == UInt8(level) })
        }
    }

    /// DDSD_MIPMAPCOUNT flag absent -> single level regardless of the count field.
    @Test func missingMipFlagMeansSingleLevel() throws {
        let data = DDSFixture.file(
            flags: 0x1007,
            width: 4,
            height: 4,
            mipCount: 0,
            fourCC: "DXT1",
            payload: Data(count: 8)
        )
        #expect(try DDSFile(data: data).mipCount == 1)
    }

    @Test func rejectsBadMagic() {
        let data = DDSFixture.file(
            magic: "XDS ",
            width: 4,
            height: 4,
            fourCC: "DXT1",
            payload: Data(count: 8)
        )
        #expect(throws: DDSError.malformed("bad magic (expected \"DDS \")")) {
            try DDSFile(data: data)
        }
    }

    @Test func rejectsTruncatedMipChain() {
        var data = DDSFixture.file(format: .bc1, width: 8, height: 8, mipCount: 4)
        data.removeLast(4)
        #expect(throws: DDSError.self) { try DDSFile(data: data) }
    }

    @Test func rejectsMipCountBeyondFullChain() {
        let data = DDSFixture.file(format: .bc1, width: 8, height: 8, mipCount: 5)
        #expect(throws: DDSError.malformed("mip count 5 exceeds full chain 4")) {
            try DDSFile(data: data)
        }
    }

    @Test func rejectsCubemapCaps() {
        let data = DDSFixture.file(
            width: 4,
            height: 4,
            fourCC: "DXT1",
            caps2: 0x200,
            payload: Data(count: 8)
        )
        #expect(throws: DDSError.unsupported("cubemap")) { try DDSFile(data: data) }
    }

    @Test func rejectsVolumeCaps() {
        let data = DDSFixture.file(
            width: 4,
            height: 4,
            fourCC: "DXT1",
            caps2: 0x200000,
            payload: Data(count: 8)
        )
        #expect(throws: DDSError.unsupported("volume texture")) { try DDSFile(data: data) }
    }

    @Test func rejectsDX10Cubemap() {
        let data = DDSFixture.file(
            width: 4,
            height: 4,
            fourCC: "DX10",
            dx10: .init(dxgiFormat: 98, miscFlag: 0x4),
            payload: Data(count: 16)
        )
        #expect(throws: DDSError.unsupported("cubemap")) { try DDSFile(data: data) }
    }

    @Test func rejectsDX10Array() {
        let data = DDSFixture.file(
            width: 4,
            height: 4,
            fourCC: "DX10",
            dx10: .init(dxgiFormat: 98, arraySize: 6),
            payload: Data(count: 16 * 6)
        )
        #expect(throws: DDSError.unsupported("texture array of 6")) { try DDSFile(data: data) }
    }

    @Test func rejectsDX10NonTexture2D() {
        let data = DDSFixture.file(
            width: 4,
            height: 4,
            fourCC: "DX10",
            dx10: .init(dxgiFormat: 98, resourceDimension: 4), // TEXTURE3D
            payload: Data(count: 16)
        )
        #expect(throws: DDSError.unsupported("resource dimension 4")) { try DDSFile(data: data) }
    }

    @Test(arguments: [UInt32(0), 28, 81, 84, 87, 88])
    func rejectsUnknownDXGIFormat(dxgi: UInt32) {
        let data = DDSFixture.file(
            width: 4,
            height: 4,
            fourCC: "DX10",
            dx10: .init(dxgiFormat: dxgi),
            payload: Data(count: 16)
        )
        #expect(throws: DDSError.unsupported("DXGI format \(dxgi)")) { try DDSFile(data: data) }
    }

    @Test func rejectsUnknownFourCC() {
        let data = DDSFixture.file(
            width: 4,
            height: 4,
            fourCC: "RGBG",
            payload: Data(count: 16)
        )
        #expect(throws: DDSError.unsupported("FourCC RGBG")) { try DDSFile(data: data) }
    }
}

@Suite(.tags(.parser))
struct DDSUncompressedFileTests {
    @Test func decodesRGBA8888ObjectAtlasLayout() throws {
        let file = try DDSFile(data: DDSFixture.rgba8888File(
            width: 8,
            height: 4,
            mipCount: 4
        ))
        #expect(file.format == .rgba8888)
        #expect(file.mipCount == 4)
        #expect((0 ..< 4).map { file.bytesPerRow(level: $0) } == [32, 16, 8, 4])
        #expect((0 ..< 4).map { file.mipData(level: $0).count } == [128, 32, 8, 4])
    }

    @Test func decodesBGRA8888TreeAtlasLayout() throws {
        let file = try DDSFile(data: DDSFixture.bgra8888File(
            width: 8,
            height: 4,
            mipCount: 4
        ))
        #expect(file.format == .bgra8888)
        #expect(file.mipCount == 4)
        #expect((0 ..< 4).map { file.bytesPerRow(level: $0) } == [32, 16, 8, 4])
        #expect((0 ..< 4).map { file.mipData(level: $0).count } == [128, 32, 8, 4])
    }

    @Test func rejectsUnsupportedUncompressedPixelFlags() {
        let data = DDSFixture.xrgb8888File(
            width: 4,
            height: 4,
            mipCount: 1,
            pixelFlags: 0x42 // DDPF_RGB absent
        )
        #expect(throws: DDSError.unsupported("uncompressed pixel flags 0x42")) {
            try DDSFile(data: data)
        }
    }

    @Test func rejectsWrongUncompressedBitCount() {
        let data = DDSFixture.xrgb8888File(
            width: 4,
            height: 4,
            mipCount: 1,
            bitCount: 16
        )
        #expect(throws: DDSError.unsupported("uncompressed RGB bit count 16")) {
            try DDSFile(data: data)
        }
    }

    @Test func widensTwentyFourBitBGRToOpaqueXRGB() throws {
        let file = try DDSFile(data: rgb24File(
            width: 2, height: 1, flags: 0x100F, size: 6, payload: Data([3, 2, 1, 30, 20, 10])
        ))
        #expect(file.format == .xrgb8888)
        #expect(file.bytesPerRow(level: 0) == 8)
        #expect([UInt8](file.mipData(level: 0)) == [3, 2, 1, 255, 30, 20, 10, 255])
    }

    @Test func widensTwentyFourBitRGBWithLinearSizeAndMips() throws {
        let file = try DDSFile(data: rgb24File(
            width: 2, height: 2, flags: 0x81007, size: 12, mipCount: 2,
            redMask: 0x0000_00FF, blueMask: 0x00FF_0000,
            payload: Data(repeating: 0, count: 12) + Data([1, 2, 3])
        ))
        #expect(file.mipCount == 2)
        #expect(file.mipData(level: 0).count == 16)
        #expect([UInt8](file.mipData(level: 1)) == [3, 2, 1, 255])
    }

    @Test func rejectsTwentyFourBitWithWrongSizeOrMasks() {
        let wrongSize = rgb24File(
            width: 2,
            height: 1,
            flags: 0x100F,
            size: 8,
            payload: Data(count: 6)
        )
        #expect(throws: DDSError.malformed("uncompressed pitch 8 != expected 6")) {
            try DDSFile(data: wrongSize)
        }
        let sharedByte = rgb24File(
            width: 2, height: 1, flags: 0x1007, size: 0, blueMask: 0x00FF_0000,
            payload: Data(count: 6)
        )
        #expect(throws: DDSError.unsupported("24-bit RGB channel masks")) {
            try DDSFile(data: sharedByte)
        }
    }

    private func rgb24File(
        width: UInt32, height: UInt32, flags: UInt32, size: UInt32, mipCount: UInt32 = 0,
        redMask: UInt32 = 0x00FF_0000, blueMask: UInt32 = 0x0000_00FF, payload: Data
    ) -> Data {
        DDSFixture.file(
            flags: flags, width: width, height: height, pitchOrLinearSize: size,
            mipCount: mipCount, pixelFlags: 0x40, fourCC: "\0\0\0\0", rgbBitCount: 24,
            redMask: redMask, greenMask: 0x0000_FF00, blueMask: blueMask, payload: payload
        )
    }

    @Test(arguments: [
        (UInt32(0), UInt32(0x0000_FF00), UInt32(0x0000_00FF), UInt32(0)),
        (UInt32(0x00FF_0000), UInt32(0), UInt32(0x0000_00FF), UInt32(0)),
        (UInt32(0x00FF_0000), UInt32(0x0000_FF00), UInt32(0), UInt32(0)),
        (UInt32(0x00FF_0000), UInt32(0x0000_FF00), UInt32(0x0000_00FF), UInt32(0xFF00_0000))
    ])
    func rejectsWrongUncompressedMasks(
        red: UInt32,
        green: UInt32,
        blue: UInt32,
        alpha: UInt32
    ) {
        let data = DDSFixture.xrgb8888File(
            width: 4,
            height: 4,
            mipCount: 1,
            redMask: red,
            greenMask: green,
            blueMask: blue,
            alphaMask: alpha
        )
        #expect(throws: DDSError.unsupported("uncompressed RGB channel masks")) {
            try DDSFile(data: data)
        }
    }

    @Test(arguments: [(UInt32(0x81007), UInt32(64)), (0x1007, 0)])
    func acceptsLinearSizeOrNoSizeField(flags: UInt32, size: UInt32) throws {
        let data = DDSFixture.xrgb8888File(
            width: 4,
            height: 4,
            mipCount: 1,
            flags: flags,
            pitch: size
        )
        #expect(try DDSFile(data: data).format == .xrgb8888)
    }

    @Test func rejectsWrongUncompressedLinearSize() {
        let data = DDSFixture.xrgb8888File(
            width: 4,
            height: 4,
            mipCount: 1,
            flags: 0x81007,
            pitch: 16
        )
        #expect(throws: DDSError.malformed("uncompressed pitch 16 != expected 64")) {
            try DDSFile(data: data)
        }
    }

    @Test func rejectsWrongUncompressedPitch() {
        let data = DDSFixture.xrgb8888File(
            width: 4,
            height: 4,
            mipCount: 1,
            pitch: 20
        )
        #expect(throws: DDSError.malformed("uncompressed pitch 20 != expected 16")) {
            try DDSFile(data: data)
        }
    }

    @Test func rejectsTruncatedUncompressedMipChain() {
        let payload = Data(count: 4 * 4 * 4 + 2 * 2 * 4 - 1)
        let data = DDSFixture.xrgb8888File(
            width: 4,
            height: 4,
            mipCount: 2,
            payload: payload
        )
        #expect(throws: DDSError.self) { try DDSFile(data: data) }
    }

    @Test func rejectsZeroDimension() {
        let data = DDSFixture.file(width: 0, height: 4, fourCC: "DXT1", payload: Data(count: 8))
        #expect(throws: DDSError.malformed("dimensions 0x4 out of range")) {
            try DDSFile(data: data)
        }
    }

    @Test func rejectsTruncatedHeader() {
        let data = DDSFixture.file(format: .bc1, width: 4, height: 4, mipCount: 1).prefix(60)
        #expect(throws: (any Error).self) { try DDSFile(data: Data(data)) }
    }
}
