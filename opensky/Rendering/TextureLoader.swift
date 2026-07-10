// Parsed DDS -> MTLTexture upload. BCn pixel formats are sampled natively on
// Apple Silicon, so upload is a straight per-mip replace — no CPU decode.
// Color space is the caller's call per usage (todo 2.5): diffuse maps want
// the sRGB view, normal/data maps stay linear. Any failure (parse, format,
// allocation) falls back to a 1x1 placeholder and logs — a bad texture must
// never take down the engine (AGENTS.md mod-quirk rule).

import Foundation
import Metal
import os

/// How a texture is consumed — decides color space and the placeholder pixel.
nonisolated enum TextureUsage {
    /// Color data (diffuse/albedo): sRGB pixel format, mid-gray placeholder.
    case color
    /// Non-color data (normal, specular, masks): linear format, flat-normal
    /// placeholder (128, 128, 255).
    case data
}

nonisolated enum TextureLoaderError: Error, Equatable {
    /// Device cannot sample BCn (never on Apple Silicon; paravirtual CI GPUs).
    case bcTextureCompressionUnsupported
    case textureAllocationFailed
}

/// Uploads DDS bytes to `MTLTexture`s. One per device; placeholders are
/// created once and shared across every failed load.
nonisolated final class TextureLoader {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "TextureLoader"
    )

    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    /// Never fails: parse/upload errors log once and yield the usage's 1x1
    /// placeholder so scene build keeps going (todo 2.5 fallback rule).
    func texture(dds data: Data, usage: TextureUsage, label: String) -> MTLTexture {
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
    func missingTexture(usage: TextureUsage, label: String) -> MTLTexture {
        Self.logger.error("texture \(label, privacy: .public) missing, using placeholder")
        return placeholder(usage: usage)
    }

    /// Throwing core — exercised directly by unit tests.
    func upload(dds: DDSFile, usage: TextureUsage, label: String) throws -> MTLTexture {
        guard device.supportsBCTextureCompression else {
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
            dds.mipData(level: level).withUnsafeBytes { bytes in
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

    /// BCn -> MTLPixelFormat. `usage == .color` picks the sRGB view; BC4/BC5
    /// have no sRGB variants (single/dual channel data formats).
    static func pixelFormat(for format: DDSPixelFormat, usage: TextureUsage) -> MTLPixelFormat {
        let srgb = usage == .color
        switch format {
        case .bc1: return srgb ? .bc1_rgba_srgb : .bc1_rgba
        case .bc2: return srgb ? .bc2_rgba_srgb : .bc2_rgba
        case .bc3: return srgb ? .bc3_rgba_srgb : .bc3_rgba
        case .bc4: return .bc4_rUnorm
        case .bc5: return .bc5_rgUnorm
        case .bc7: return srgb ? .bc7_rgbaUnorm_srgb : .bc7_rgbaUnorm
        }
    }

    // MARK: - Placeholders

    /// Lazy per-usage cache; the loader is used from one thread (scene build).
    private var placeholders: [MTLTexture?] = [nil, nil]

    private func placeholder(usage: TextureUsage) -> MTLTexture {
        let slot = usage == .color ? 0 : 1
        if let texture = placeholders[slot] { return texture }
        let texture = makePlaceholder(usage: usage)
        placeholders[slot] = texture
        return texture
    }

    /// 1x1 RGBA8: mid-gray for color (lighting still shades it), flat normal
    /// for data. Plain formats — `makeTexture` for these cannot reasonably
    /// fail; if it somehow does the renderer cannot draw anything anyway.
    private func makePlaceholder(usage: TextureUsage) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = usage == .color ? .rgba8Unorm_srgb : .rgba8Unorm
        descriptor.width = 1
        descriptor.height = 1
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("cannot allocate 1x1 placeholder texture")
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
