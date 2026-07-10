// DDS -> MTLTexture upload tests over synthetic DDS bytes (DDSFixture).
// GPU tests skip when no Metal device (or no BCn support — paravirtual CI).

import Foundation
import Metal
@testable import opensky
import Testing

struct TextureLoaderTests {
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

    private func loader() throws -> TextureLoader {
        let device = try #require(Self.bcDevice, "no BCn-capable Metal device")
        return TextureLoader(device: device)
    }

    @Test(arguments: [
        (DDSPixelFormat.bc1, TextureUsage.color, MTLPixelFormat.bc1_rgba_srgb),
        (.bc1, .data, .bc1_rgba),
        (.bc2, .color, .bc2_rgba_srgb),
        (.bc3, .color, .bc3_rgba_srgb),
        (.bc4, .color, .bc4_rUnorm), // no sRGB variant
        (.bc5, .data, .bc5_rgUnorm),
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
        let texture = try loader().upload(dds: dds, usage: .color, label: "test-bc7")
        #expect(texture.width == 16)
        #expect(texture.height == 8)
        #expect(texture.mipmapLevelCount == 5)
        #expect(texture.pixelFormat == .bc7_rgbaUnorm_srgb)
        #expect(texture.textureType == .type2D)
        #expect(texture.label == "test-bc7")
    }

    @Test(.enabled(if: Self.hasBCDevice)) func malformedBytesFallBackToPlaceholder() throws {
        let texture = try loader().texture(
            dds: Data("not a dds file".utf8),
            usage: .color,
            label: "garbage"
        )
        #expect(texture.width == 1)
        #expect(texture.height == 1)
        #expect(texture.pixelFormat == .rgba8Unorm_srgb)
    }

    @Test(.enabled(if: Self.hasBCDevice)) func placeholderMatchesUsageAndIsShared() throws {
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
