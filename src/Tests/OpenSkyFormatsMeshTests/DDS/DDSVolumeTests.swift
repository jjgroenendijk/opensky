// DDS volume textures and 8-bit luminance over synthetic in-code files (DDSFixture).

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct DDSVolumeTests {
    private static let volumeCaps: UInt32 = 0x200000 // DDSCAPS2_VOLUME
    private static let luminanceFlags: UInt32 = 0x20000 // DDPF_LUMINANCE

    /// An L8 volume whose bytes each hold their mip level, like `noisevolume.dds`.
    private static func luminanceVolume(size: Int, mipCount: Int, cut: Int = 0) -> Data {
        var payload = Data()
        for level in 0 ..< mipCount {
            let edge = max(1, size >> level)
            payload.append(Data(repeating: UInt8(level + 1), count: edge * edge * edge))
        }
        return DDSFixture.file(
            width: UInt32(size), height: UInt32(size), depth: UInt32(size),
            mipCount: UInt32(mipCount), pixelFlags: luminanceFlags, fourCC: "\0\0\0\0",
            rgbBitCount: 8, redMask: 0xFF, caps2: volumeCaps,
            payload: payload.dropLast(cut)
        )
    }

    @Test func readsALuminanceVolumeWithItsMipChain() throws {
        let file = try DDSFile(data: Self.luminanceVolume(size: 4, mipCount: 3), allowsVolume: true)
        #expect(file.depth == 4)
        #expect(file.faceCount == 1)
        #expect(file.format == .xrgb8888)
        #expect((0 ..< 3).map { file.depth(level: $0) } == [4, 2, 1])
        #expect((0 ..< 3).map { file.mipData(level: $0).count } == [256, 32, 4])
        #expect(file.bytesPerRow(level: 0) == 16)
        #expect(file.bytesPerImage(level: 0) == 64)
        #expect(Array(file.mipData(level: 1).prefix(4)) == [2, 2, 2, 255])
    }

    @Test func declaresVolumeReadsOnlyTheHeaders() {
        #expect(DDSFile.declaresVolume(Self.luminanceVolume(size: 4, mipCount: 3, cut: 1)))
        let dx10 = DDSFixture.file(
            width: 4, height: 4, depth: 2, fourCC: "DX10",
            dx10: .init(dxgiFormat: 98, resourceDimension: 4), payload: Data()
        )
        #expect(DDSFile.declaresVolume(dx10))
        let flat = DDSFixture.file(width: 4, height: 4, fourCC: "DXT1", payload: Data(count: 8))
        #expect(!DDSFile.declaresVolume(flat))
        #expect(!DDSFile.declaresVolume(Data("DDS ".utf8)))
    }

    @Test func rejectsAVolumeUnlessTheCallerAllowsIt() {
        #expect(throws: DDSError.unsupported("volume texture")) {
            try DDSFile(data: Self.luminanceVolume(size: 4, mipCount: 1))
        }
    }

    @Test func rejectsATruncatedVolume() {
        let data = Self.luminanceVolume(size: 4, mipCount: 3, cut: 1)
        #expect(throws: DDSError.self) { try DDSFile(data: data, allowsVolume: true) }
    }

    @Test func countsDepthInTheFullMipChain() throws {
        let data = DDSFixture.file(
            width: 1, height: 1, depth: 4, mipCount: 3, fourCC: "DXT1", caps2: Self.volumeCaps,
            payload: Data(count: 8 * (4 + 2 + 1))
        )
        let file = try DDSFile(data: data, allowsVolume: true)
        #expect(file.mipCount == 3)
        #expect(file.mipData(level: 0).count == 32)
    }

    @Test func readsADX10Texture3D() throws {
        let data = DDSFixture.file(
            width: 4, height: 4, depth: 2, fourCC: "DX10",
            dx10: .init(dxgiFormat: 98, resourceDimension: 4),
            payload: Data(count: 16 * 2)
        )
        let file = try DDSFile(data: data, allowsVolume: true)
        #expect(file.depth == 2)
        #expect(file.format == .bc7)
        #expect(throws: DDSError.unsupported("volume texture")) { try DDSFile(data: data) }
    }

    @Test func ignoresDepthOnA2DTexture() throws {
        let data = DDSFixture.file(
            width: 4, height: 4, depth: 9, fourCC: "DXT1", payload: Data(count: 8)
        )
        #expect(try DDSFile(data: data).depth == 1)
    }

    @Test func rejectsAVolumeWithZeroDepth() {
        let data = DDSFixture.file(
            width: 4, height: 4, fourCC: "DXT1", caps2: Self.volumeCaps, payload: Data(count: 8)
        )
        #expect(throws: DDSError.malformed("volume depth 0 out of range")) {
            try DDSFile(data: data, allowsVolume: true)
        }
    }

    @Test func widensA2DLuminanceTextureToGrey() throws {
        let data = DDSFixture.file(
            width: 2, height: 1, pixelFlags: Self.luminanceFlags, fourCC: "\0\0\0\0",
            rgbBitCount: 8, redMask: 0xFF, payload: Data([10, 200])
        )
        let file = try DDSFile(data: data)
        #expect([UInt8](file.mipData(level: 0)) == [10, 10, 10, 255, 200, 200, 200, 255])
        #expect(file.bytesPerRow(level: 0) == 8)
    }

    @Test func rejectsLuminanceWithAlphaOrWiderTexels() {
        let withAlpha = DDSFixture.file(
            width: 1, height: 1, pixelFlags: Self.luminanceFlags | 0x1, fourCC: "\0\0\0\0",
            rgbBitCount: 16, redMask: 0xFF, alphaMask: 0xFF00, payload: Data(count: 2)
        )
        #expect(throws: DDSError.unsupported("luminance flags 0x20001, bit count 16")) {
            try DDSFile(data: withAlpha)
        }
    }

    @Test func censusNamesTheVolumeVariant() {
        var census = DDSGapCensus()
        census.record(data: Self.luminanceVolume(size: 2, mipCount: 1))
        #expect(census.variants.uses["xrgb8888 volume"] == 1)
        #expect(census.variants.left(where: DDSGapCensus.isRead).isEmpty)
    }
}
