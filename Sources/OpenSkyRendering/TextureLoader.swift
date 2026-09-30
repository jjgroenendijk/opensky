// Parsed DDS -> MTLTexture upload. Color maps use the sRGB view; data maps stay
// linear. A failed load logs and falls back to a 1x1 placeholder, so one bad
// texture never stops the engine.

import Foundation
import Metal
import OpenSkyFormatsMesh
import os

/// How a texture is consumed — decides color space and the placeholder pixel.
nonisolated public enum TextureUsage: Sendable {
    /// Color data (diffuse/albedo): sRGB pixel format, mid-gray placeholder.
    case color
    /// Non-color data (normal, specular, masks): linear format, flat-normal
    /// placeholder (128, 128, 255).
    case data
}

nonisolated public enum TextureLoaderError: Error, Equatable {
    /// Device cannot sample BCn (never on Apple Silicon; paravirtual CI GPUs).
    case bcTextureCompressionUnsupported
    case textureAllocationFailed
    case placeholderAllocationFailed
}

/// Uploads DDS bytes to `MTLTexture`s. One per device; placeholders are
/// created once and shared across every failed load.
nonisolated public final class TextureLoader {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "TextureLoader"
    )

    private let device: MTLDevice
    private let colorPlaceholder: MTLTexture
    private let dataPlaceholder: MTLTexture

    /// Throws when the 1x1 placeholders cannot be allocated, because then no
    /// failed load has a fallback.
    public init(device: MTLDevice) throws {
        self.device = device
        colorPlaceholder = try Self.makePlaceholder(device: device, usage: .color)
        dataPlaceholder = try Self.makePlaceholder(device: device, usage: .data)
    }

    /// Never fails: a parse or upload error logs and yields the usage's placeholder.
    public func texture(dds data: Data, usage: TextureUsage, label: String) -> MTLTexture {
        do {
            return try upload(dds: DDSFile(data: data), usage: usage, label: label)
        } catch {
            Self.logger.error(
                """
                texture \(label, privacy: .public) failed \
                (\(String(describing: error), privacy: .public)), using placeholder
                """
            )
            return placeholder(usage: usage)
        }
    }

    /// Missing file (VFS lookup failed upstream): log + placeholder.
    public func missingTexture(usage: TextureUsage, label: String) -> MTLTexture {
        Self.logger.error("texture \(label, privacy: .public) missing, using placeholder")
        return placeholder(usage: usage)
    }

    /// Throwing core — exercised directly by unit tests.
    public func upload(dds: DDSFile, usage: TextureUsage, label: String) throws -> MTLTexture {
        guard !dds.format.isBlockCompressed || device.supportsBCTextureCompression else {
            throw TextureLoaderError.bcTextureCompressionUnsupported
        }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = Self.pixelFormat(for: dds.format, usage: usage)
        descriptor.width = dds.width
        descriptor.height = dds.height
        descriptor.mipmapLevelCount = dds.mipCount
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared // unified memory, no blit staging

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TextureLoaderError.textureAllocationFailed
        }
        texture.label = label

        for level in 0 ..< dds.mipCount {
            let region = MTLRegionMake2D(
                0,
                0,
                dds.width(level: level),
                dds.height(level: level)
            )
            let source = dds.mipData(level: level)
            let uploadData = dds.format == .xrgb8888 ? Self.withOpaqueAlpha(source) : source
            uploadData.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return } // levels never empty
                texture.replace(
                    region: region,
                    mipmapLevel: level,
                    withBytes: base,
                    bytesPerRow: dds.bytesPerRow(level: level)
                )
            }
        }
        return texture
    }

    /// xRGB stores B,G,R,X bytes per little-endian channel masks. Metal's
    /// BGRA8 format consumes the same byte order, but X is undefined -> 255.
    private static func withOpaqueAlpha(_ source: Data) -> Data {
        var result = source
        for offset in stride(from: 3, to: result.count, by: 4) {
            result[offset] = 255
        }
        return result
    }

    /// BCn -> MTLPixelFormat. `usage == .color` picks the sRGB view; BC4/BC5
    /// have no sRGB variants (single/dual channel data formats).
    public static func pixelFormat(
        for format: DDSPixelFormat,
        usage: TextureUsage
    ) -> MTLPixelFormat {
        let srgb = usage == .color
        switch format {
        case .bc1: return srgb ? .bc1_rgba_srgb : .bc1_rgba
        case .bc2: return srgb ? .bc2_rgba_srgb : .bc2_rgba
        case .bc3: return srgb ? .bc3_rgba_srgb : .bc3_rgba
        case .bc4: return .bc4_rUnorm
        case .bc5: return .bc5_rgUnorm
        case .rgba8888: return srgb ? .rgba8Unorm_srgb : .rgba8Unorm
        case .bgra8888, .xrgb8888: return srgb ? .bgra8Unorm_srgb : .bgra8Unorm
        case .bc7: return srgb ? .bc7_rgbaUnorm_srgb : .bc7_rgbaUnorm
        }
    }

    // MARK: - Placeholders

    private func placeholder(usage: TextureUsage) -> MTLTexture {
        usage == .color ? colorPlaceholder : dataPlaceholder
    }

    /// 1x1 RGBA8: mid-gray for color (lighting still shades it), flat normal for data.
    private static func makePlaceholder(
        device: MTLDevice,
        usage: TextureUsage
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = usage == .color ? .rgba8Unorm_srgb : .rgba8Unorm
        descriptor.width = 1
        descriptor.height = 1
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TextureLoaderError.placeholderAllocationFailed
        }
        texture.label = usage == .color ? "placeholder-color" : "placeholder-data"
        var pixel: [UInt8] = usage == .color ? [128, 128, 128, 255] : [128, 128, 255, 255]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &pixel,
            bytesPerRow: 4
        )
        return texture
    }
}
