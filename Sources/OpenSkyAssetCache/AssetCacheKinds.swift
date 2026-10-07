// The kinds of converted assets and the quality presets they are built for.
// See docs/engine/asset-cache.md.

import Foundation

nonisolated public enum AssetCacheKind: UInt8, CaseIterable, Sendable, CustomStringConvertible {
    case texture = 1
    case mesh = 2
    case collision = 3
    case animation = 4
    case audio = 5

    /// The folder inside the cache root that holds this kind's entries.
    public var folderName: String {
        switch self {
        case .texture: "textures"
        case .mesh: "meshes"
        case .collision: "collision"
        case .animation: "animation"
        case .audio: "audio"
        }
    }

    public var description: String {
        folderName
    }
}

/// How converted assets trade build time, GPU memory, and disk size against looks.
nonisolated public enum AssetQualityPreset: UInt8, CaseIterable, Sendable, CustomStringConvertible {
    case bestPerformance = 0
    case balanced = 1
    case highestQuality = 2

    public static let `default` = Self.balanced

    public var title: String {
        switch self {
        case .bestPerformance: "Best performance"
        case .balanced: "Balanced"
        case .highestQuality: "Highest quality"
        }
    }

    public var description: String {
        title
    }
}

nonisolated extension AssetQualityPreset {
    private static let gibibyte: UInt64 = 1 << 30

    /// The whole base-game cache for this preset, from the format comparison census:
    /// textures, meshes, collision, animation, and ALAC audio.
    public var estimatedBaseGameCacheBytes: UInt64 {
        switch self {
        case .bestPerformance: 13 * Self.gibibyte
        case .balanced: 22 * Self.gibibyte
        case .highestQuality: 26 * Self.gibibyte
        }
    }

    /// Fits the whole base-game cache with a tenth to spare, in whole GiB.
    public var defaultLimitBytes: UInt64 {
        let withMargin = estimatedBaseGameCacheBytes + estimatedBaseGameCacheBytes / 10
        return (withMargin + Self.gibibyte - 1) / Self.gibibyte * Self.gibibyte
    }
}
