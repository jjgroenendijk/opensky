// The texture converter for every preset. A texture the preset keeps shipped is
// stored as it is; one it compresses is decoded by the GPU, level by level, and
// re-encoded as ASTC at the fastest effort. The GPU decode is the reference,
// because it is what the renderer shows. See docs/engine/asset-cache.md.

import Foundation
import Metal
import OpenSkyAssetCache
import Synchronization

nonisolated public final class ASTCTextureConverter: AssetConverting, Sendable {
    private struct Decoder {
        let loader: TextureLoader
        let readback: TextureReadback
    }

    /// The GPU decode is serialized; the astcenc encode of different files runs in parallel.
    private let decoder: Mutex<Decoder>

    public init(device: MTLDevice, library: MTLLibrary) throws {
        decoder = try Mutex(Decoder(
            loader: TextureLoader(device: device),
            readback: TextureReadback(device: device, library: library)
        ))
    }

    public var kind: AssetCacheKind {
        .texture
    }

    public var version: UInt32 {
        AssetConverterVersion.texture
    }

    public func accepts(path: String) -> Bool {
        path.hasSuffix(".dds")
    }

    public func convert(path: String, bytes: Data, preset: AssetQualityPreset) throws -> Data? {
        guard let shipped = try ReadyTexture.shipped(dds: bytes) else { return nil }
        guard let format = preset.values.textureStorage(forPath: path).readyFormat else {
            return ReadyTextureCodec.encode(shipped)
        }
        return try ReadyTextureCodec.encode(encode(shipped, as: format))
    }

    /// Every level of `texture` decoded to RGBA8 by the GPU.
    public func decodedLevels(of texture: ReadyTexture) throws -> [TexturePixels] {
        try decoder.withLock { decoder in
            let uploaded = try decoder.loader.upload(
                ready: texture,
                usage: .data,
                label: "astc-source"
            )
            let readback = decoder.readback
            return try (0 ..< texture.mipCount).map { try readback.pixels(of: uploaded, level: $0) }
        }
    }

    public func encode(
        _ texture: ReadyTexture,
        as format: ReadyTextureFormat
    ) throws -> ReadyTexture {
        let block = ASTCBlockSize(width: format.blockDimension, height: format.blockDimension)
        var bytes = Data()
        for level in try decodedLevels(of: texture) {
            try bytes.append(ASTCEncoder.encode(level, block: block, effort: .fastest))
        }
        return ReadyTexture(
            format: format, width: texture.width, height: texture.height,
            mipCount: texture.mipCount,
            bytes: bytes
        )
    }
}
