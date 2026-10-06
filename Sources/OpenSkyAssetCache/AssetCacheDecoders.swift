// The converter version and payload decoder of each cached asset kind. A change
// to a payload layout or to what a converter produces bumps its version, which
// makes every entry it built stale.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh

nonisolated public enum AssetConverterVersion {
    public static let texture: UInt32 = 1
    public static let mesh: UInt32 = 1
    public static let collision: UInt32 = 1
    public static let animation: UInt32 = 1
    public static let audio: UInt32 = 1
}

nonisolated extension AssetCacheDecoder where Value == ReadyTexture {
    public static var readyTexture: Self {
        Self(kind: .texture, converterVersion: AssetConverterVersion.texture) {
            try ReadyTextureCodec.decode($0)
        }
    }
}

nonisolated extension AssetCacheDecoder where Value == Model {
    public static var model: Self {
        Self(kind: .mesh, converterVersion: AssetConverterVersion.mesh) {
            try ModelCacheCodec.decode($0)
        }
    }
}

nonisolated extension AssetCacheDecoder where Value == NIFCollisionModel {
    public static var collision: Self {
        Self(kind: .collision, converterVersion: AssetConverterVersion.collision) {
            try CollisionCacheCodec.decode($0)
        }
    }
}

nonisolated extension AssetCacheDecoder where Value == Data {
    /// The shipped file, extracted loose. A copy, so the mapped file can close.
    public static var looseAnimation: Self {
        Self(kind: .animation, converterVersion: AssetConverterVersion.animation) {
            Data($0)
        }
    }
}
