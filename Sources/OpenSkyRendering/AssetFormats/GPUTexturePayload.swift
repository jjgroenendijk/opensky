// A texture in the exact byte layout the GPU samples: every mip level's
// blocks or pixels, back to back. A cache file holds these bytes, so loading
// is a copy, with no parse.

import Foundation
import Metal
import OpenSkyFormatsMesh

nonisolated public enum GPUTexturePayloadError: Error, Equatable, Sendable {
    case noLevels
    case levelSizeMismatch(level: Int)
}

nonisolated public struct GPUTextureLevel: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let offset: Int
    public let length: Int
}

/// One mip level's bytes before they are packed into a payload.
nonisolated public struct GPUTextureLevelBytes: Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let bytes: Data

    public init(width: Int, height: Int, bytesPerRow: Int, bytes: Data) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.bytes = bytes
    }
}

nonisolated public struct GPUTexturePayload: Sendable {
    /// Always the linear variant: the sRGB view decodes the same bytes.
    public let pixelFormat: MTLPixelFormat
    public let levels: [GPUTextureLevel]
    public let bytes: Data

    public var width: Int {
        levels.first?.width ?? 0
    }

    public var height: Int {
        levels.first?.height ?? 0
    }

    /// Builds the payload from per-level bytes, largest first.
    public init(
        pixelFormat: MTLPixelFormat,
        levels: [GPUTextureLevelBytes]
    ) throws {
        guard !levels.isEmpty else { throw GPUTexturePayloadError.noLevels }
        var layout: [GPUTextureLevel] = []
        var bytes = Data()
        for level in levels {
            layout.append(GPUTextureLevel(
                width: level.width, height: level.height, bytesPerRow: level.bytesPerRow,
                offset: bytes.count, length: level.bytes.count
            ))
            bytes.append(level.bytes)
        }
        self.pixelFormat = pixelFormat
        self.levels = layout
        self.bytes = bytes
    }

    /// The shipped DDS blocks, with the `droppedLevels` largest levels left out.
    public static func shipped(_ dds: DDSFile, droppedLevels: Int = 0) throws -> Self {
        let first = min(droppedLevels, dds.mipCount - 1)
        return try Self(
            pixelFormat: TextureLoader.pixelFormat(for: dds.format, usage: .data),
            levels: (first ..< dds.mipCount).map { level in
                let data = dds.mipData(level: level)
                return GPUTextureLevelBytes(
                    width: dds.width(level: level), height: dds.height(level: level),
                    bytesPerRow: dds.bytesPerRow(level: level),
                    bytes: dds.format == .xrgb8888 ? TextureLoader.withOpaqueAlpha(data) : data
                )
            }
        )
    }

    public static func rgba8(levels: [TexturePixels]) throws -> Self {
        try Self(
            pixelFormat: .rgba8Unorm,
            levels: levels.map {
                GPUTextureLevelBytes(
                    width: $0.width, height: $0.height, bytesPerRow: $0.width * 4,
                    bytes: Data($0.rgba)
                )
            }
        )
    }

    /// Encodes every level with astcenc.
    public static func astc(
        levels: [TexturePixels],
        block: ASTCBlockSize,
        effort: ASTCEffort
    ) throws -> Self {
        guard let format = block.pixelFormat else {
            throw ASTCEncoderError.unsupportedBlock(width: block.width, height: block.height)
        }
        return try Self(
            pixelFormat: format,
            levels: levels.map { level in
                try GPUTextureLevelBytes(
                    width: level.width, height: level.height,
                    bytesPerRow: ASTCEncoder.bytesPerRow(width: level.width, block: block),
                    bytes: ASTCEncoder.encode(level, block: block, effort: effort)
                )
            }
        )
    }

    public func makeEmptyTexture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.mipmapLevelCount = levels.count
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TextureLoaderError.textureAllocationFailed
        }
        return texture
    }

    /// The CPU path: copies `source`, laid out as `bytes`, into a new texture.
    public func upload(device: MTLDevice, source: Data) throws -> MTLTexture {
        guard source.count == bytes.count else {
            throw GPUTexturePayloadError.levelSizeMismatch(level: 0)
        }
        let texture = try makeEmptyTexture(device: device)
        source.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for (index, level) in levels.enumerated() {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, level.width, level.height),
                    mipmapLevel: index,
                    withBytes: base + level.offset,
                    bytesPerRow: level.bytesPerRow
                )
            }
        }
        return texture
    }
}
