// DDS -> MTLTexture upload tests over synthetic DDS bytes (DDSFixture).
// GPU tests skip when no Metal device (or no BCn support — paravirtual CI).

import Foundation
import Metal
@testable import opensky
import Testing

struct TextureLoaderTests {
    private static let device = MTLCreateSystemDefaultDevice()

    /// nil when this machine cannot run BCn upload tests.
    private static let bcDevice: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsBCTextureCompression else { return nil }
        return device
    }()

    private static var hasBCDevice: Bool {
        bcDevice != nil
    }

    private static var hasDevice: Bool {
        device != nil
    }

    private func bcLoader() throws -> TextureLoader {
        let device = try #require(Self.bcDevice, "no BCn-capable Metal device")
        return TextureLoader(device: device)
    }

    private func loader() throws -> TextureLoader {
        let device = try #require(Self.device, "no Metal device")
        return TextureLoader(device: device)
    }

    @Test(arguments: [
        (DDSPixelFormat.bc1, TextureUsage.color, MTLPixelFormat.bc1_rgba_srgb),
        (.bc1, .data, .bc1_rgba),
        (.bc2, .color, .bc2_rgba_srgb),
        (.bc3, .color, .bc3_rgba_srgb),
        (.bc4, .color, .bc4_rUnorm), // no sRGB variant
        (.bc5, .data, .bc5_rgUnorm),
        (.rgba8888, .color, .rgba8Unorm_srgb),
        (.rgba8888, .data, .rgba8Unorm),
        (.xrgb8888, .color, .bgra8Unorm_srgb),
        (.xrgb8888, .data, .bgra8Unorm),
        (.bc7, .color, .bc7_rgbaUnorm_srgb),
        (.bc7, .data, .bc7_rgbaUnorm)
    ])
    func picksPixelFormatByUsage(
        format: DDSPixelFormat,
        usage: TextureUsage,
        expected: MTLPixelFormat
    ) {
        #expect(TextureLoader.pixelFormat(for: format, usage: usage) == expected)
    }

    @Test(.enabled(if: Self.hasBCDevice)) func uploadsFullMipChain() throws {
        let dds = try DDSFile(data: DDSFixture.file(
            format: .bc7,
            width: 16,
            height: 8,
            mipCount: 5
        ))
        let texture = try bcLoader().upload(dds: dds, usage: .color, label: "test-bc7")
        #expect(texture.width == 16)
        #expect(texture.height == 8)
        #expect(texture.mipmapLevelCount == 5)
        #expect(texture.pixelFormat == .bc7_rgbaUnorm_srgb)
        #expect(texture.textureType == .type2D)
        #expect(texture.label == "test-bc7")
    }

    @Test(.enabled(if: Self.hasDevice)) func uploadsXRGBMipChainWithOpaqueAlpha() throws {
        let payload = Data([
            10, 20, 30, 0, 40, 50, 60, 99, // level 0: 2x1 BGRX
            70, 80, 90, 1 // level 1: 1x1 BGRX
        ])
        let dds = try DDSFile(data: DDSFixture.xrgb8888File(
            width: 2,
            height: 1,
            mipCount: 2,
            payload: payload
        ))
        let texture = try loader().upload(dds: dds, usage: .color, label: "test-xrgb")
        #expect(texture.width == 2)
        #expect(texture.height == 1)
        #expect(texture.mipmapLevelCount == 2)
        #expect(texture.pixelFormat == .bgra8Unorm_srgb)

        var level0 = [UInt8](repeating: 0, count: 8)
        texture.getBytes(
            &level0,
            bytesPerRow: 8,
            from: MTLRegionMake2D(0, 0, 2, 1),
            mipmapLevel: 0
        )
        #expect(level0 == [10, 20, 30, 255, 40, 50, 60, 255])

        var level1 = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &level1,
            bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 1
        )
        #expect(level1 == [70, 80, 90, 255])
    }

    @Test(.enabled(if: Self.hasDevice)) func uploadsRGBAWithStoredAlpha() throws {
        let dds = try DDSFile(data: DDSFixture.rgba8888File(
            width: 1,
            height: 1,
            mipCount: 1,
            payload: Data([10, 20, 30, 40])
        ))
        let texture = try loader().upload(dds: dds, usage: .color, label: "test-rgba")
        #expect(texture.pixelFormat == .rgba8Unorm_srgb)

        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &pixel,
            bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )
        #expect(pixel == [10, 20, 30, 40])
    }

    @Test(.enabled(if: Self.hasDevice)) func malformedBytesFallBackToPlaceholder() throws {
        let texture = try loader().texture(
            dds: Data("not a dds file".utf8),
            usage: .color,
            label: "garbage"
        )
        #expect(texture.width == 1)
        #expect(texture.height == 1)
        #expect(texture.pixelFormat == .rgba8Unorm_srgb)
    }

    @Test(.enabled(if: Self.hasDevice)) func placeholderMatchesUsageAndIsShared() throws {
        let loader = try loader()
        let color = loader.missingTexture(usage: .color, label: "missing-diffuse")
        let data = loader.missingTexture(usage: .data, label: "missing-normal")
        #expect(color.pixelFormat == .rgba8Unorm_srgb)
        #expect(data.pixelFormat == .rgba8Unorm)
        #expect(color !== data)
        // Second miss reuses the cached texture — no per-failure allocations.
        #expect(loader.missingTexture(usage: .color, label: "again") === color)
    }
}
