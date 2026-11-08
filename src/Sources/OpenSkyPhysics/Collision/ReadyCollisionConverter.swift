// Collision models stored in the asset cache, and the decoder that reads them back.

public import Foundation
public import OpenSkyAssetCache
public import OpenSkyFormatsMesh

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

    public func convert(path _: String, bytes: Data, output _: AssetTextureOutput) throws -> Data? {
        try CollisionCacheCodec.encode(NIFFile(data: bytes).collisionModel())
    }
}

nonisolated extension AssetCacheDecoder where Value == NIFCollisionModel {
    public static var collision: Self {
        Self(kind: .collision, converterVersion: AssetConverterVersion.collision) {
            try CollisionCacheCodec.decode($0)
        }
    }
}
