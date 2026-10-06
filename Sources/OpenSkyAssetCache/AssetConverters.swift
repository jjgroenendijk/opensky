// Converters turn one source file's bytes into one cache payload. Each is pure:
// bytes and preset in, bytes out, with a version. A converter returns nil for a
// source it does not store, which then always loads from the original file.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh

nonisolated public protocol AssetConverting: Sendable {
    var kind: AssetCacheKind { get }
    var version: UInt32 { get }
    /// True for the VFS paths this converter reads, such as `.dds` files.
    func accepts(path: String) -> Bool
    func convert(path: String, bytes: Data, preset: AssetQualityPreset) throws -> Data?
}

/// Shipped textures, stored as they are: the BC blocks and mip levels, ready to upload.
nonisolated public struct ShippedTextureConverter: AssetConverting {
    public init() {}

    public var kind: AssetCacheKind {
        .texture
    }

    public var version: UInt32 {
        AssetConverterVersion.texture
    }

    public func accepts(path: String) -> Bool {
        path.hasSuffix(".dds")
    }

    public func convert(path _: String, bytes: Data, preset _: AssetQualityPreset) throws -> Data? {
        try ReadyTexture.shipped(dds: bytes).map(ReadyTextureCodec.encode)
    }
}

nonisolated extension ReadyTexture {
    /// Nil for a DDS layout the engine does not read, so the build stores the
    /// "load the original" marker instead of failing on every run.
    public static func shipped(dds bytes: Data) throws -> ReadyTexture? {
        do {
            return try ReadyTexture(dds: DDSFile(data: bytes))
        } catch DDSError.unsupported {
            return nil
        }
    }
}

/// Flattened render models. Skinned character meshes need the character skeleton
/// and particle models need their emitters, so both keep the NIF path.
nonisolated public struct ReadyMeshConverter: AssetConverting {
    public init() {}

    public var kind: AssetCacheKind {
        .mesh
    }

    public var version: UInt32 {
        AssetConverterVersion.mesh
    }

    public func accepts(path: String) -> Bool {
        path.hasSuffix(".nif")
    }

    public func convert(path: String, bytes: Data, preset _: AssetQualityPreset) throws -> Data? {
        let file = try NIFFile(data: bytes)
        if
            path.hasPrefix("meshes\\actors\\character\\"),
            file.blocks.contains(where: { $0.typeName == "NiSkinData" })
        {
            return nil
        }
        guard (try? file.particleSystems())?.isEmpty ?? false else { return nil }
        return try ModelCacheCodec.encode(file.model(skeleton: nil))
    }
}

/// Decoded collision bodies as ready arrays. Models with joints keep the NIF path.
nonisolated public struct ReadyCollisionConverter: AssetConverting {
    public init() {}

    public var kind: AssetCacheKind {
        .collision
    }

    public var version: UInt32 {
        AssetConverterVersion.collision
    }

    public func accepts(path: String) -> Bool {
        path.hasSuffix(".nif")
    }

    public func convert(path _: String, bytes: Data, preset _: AssetQualityPreset) throws -> Data? {
        try CollisionCacheCodec.encode(NIFFile(data: bytes).collisionModel())
    }
}

/// Animation stays the shipped file, extracted loose. Ready poses loaded faster
/// in the format comparison, but took many times the memory.
nonisolated public struct LooseAnimationConverter: AssetConverting {
    public init() {}

    public var kind: AssetCacheKind {
        .animation
    }

    public var version: UInt32 {
        AssetConverterVersion.animation
    }

    public func accepts(path: String) -> Bool {
        path.hasSuffix(".hkx")
    }

    public func convert(path _: String, bytes: Data, preset _: AssetQualityPreset) throws -> Data? {
        bytes
    }
}

nonisolated public enum AssetConverters {
    /// The extract converters every preset uses.
    public static let extract: [any AssetConverting] = [
        ShippedTextureConverter(), ReadyMeshConverter(), ReadyCollisionConverter(),
        LooseAnimationConverter()
    ]
}
