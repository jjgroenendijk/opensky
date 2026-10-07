// What each quality preset stores, per asset kind, in one table. The values come
// from the format comparison; docs/engine/asset-cache.md, "Presets", has the
// measurements behind them.

import Foundation

/// Which texture group a shipped texture belongs to, from its file name suffix.
nonisolated public enum AssetTextureClass: CaseIterable, Sendable {
    case color
    case normal
    case data

    /// `_n` and `_msn` are normal maps; `_s`, `_g`, `_e`, `_m`, `_p`, `_b`, and
    /// `_sk` are specular, glow, environment, mask, parallax, backlight, and skin
    /// data. Everything else is color.
    public init(path: String) {
        let name = path.lowercased().split(whereSeparator: { $0 == "\\" || $0 == "/" }).last ?? ""
        let stem = name.hasSuffix(".dds") ? name.dropLast(4) : name[...]
        if stem.hasSuffix("_n") || stem.hasSuffix("_msn") {
            self = .normal
        } else if
            ["_s", "_g", "_e", "_em", "_m", "_p", "_b", "_sk"]
                .contains(where: { stem.hasSuffix($0) })
        {
            self = .data
        } else {
            self = .color
        }
    }
}

nonisolated public enum AssetTextureStorage: Equatable, Sendable {
    /// The shipped BC blocks and mip levels, as they are.
    case shipped
    case astc4x4
    case astc6x6
    case astc8x8

    public var readyFormat: ReadyTextureFormat? {
        switch self {
        case .shipped: nil
        case .astc4x4: .astc4x4
        case .astc6x6: .astc6x6
        case .astc8x8: .astc8x8
        }
    }
}

/// Which sound group a cached sound belongs to, from its folder. Dialogue ships
/// as `.fuz` and is not cached, so `voice` holds the creature vocal sounds.
nonisolated public enum AssetSoundCategory: String, CaseIterable, Sendable {
    case effects
    case voice
    case ambience
    case music

    public init(path: String) {
        let folders = path.lowercased().split(whereSeparator: { $0 == "\\" || $0 == "/" })
        if folders.first == "music" {
            self = .music
        } else if folders.contains("voice") || folders.dropFirst(2).first == "voc" {
            self = .voice
        } else if folders.dropFirst(2).first?.hasPrefix("amb") == true {
            self = .ambience
        } else {
            self = .effects
        }
    }
}

/// The smallest image quality a converted texture may have. A color or data
/// map compares by PSNR; a normal map also by its worst normal angle.
nonisolated public struct AssetImageLimit: Equatable, Sendable {
    /// Nil means lossless: the shipped bytes.
    public let minimumPSNR: Double?
    public let maximumNormalDegrees: Double?

    public static let lossless = Self(minimumPSNR: nil, maximumNormalDegrees: nil)
}

nonisolated public struct AssetPresetValues: Equatable, Sendable {
    public let textures: [AssetTextureClass: AssetTextureStorage]
    /// Largest texture edge kept, or nil for the shipped size.
    public let maximumTextureSize: Int?
    /// Mip levels kept, or nil for every shipped level.
    public let mipLevels: Int?
    public let imageLimit: AssetImageLimit
    /// Whole-install build time on one core, in minutes, at the fastest ASTC effort.
    public let buildMinutesOneCore: Double
    public let summary: String

    public func textureStorage(forPath path: String) -> AssetTextureStorage {
        textures[AssetTextureClass(path: path)] ?? .shipped
    }
}

nonisolated extension AssetQualityPreset {
    /// Meshes and collision are ready buffers in every preset; only textures differ.
    public var values: AssetPresetValues {
        switch self {
        case .highestQuality:
            AssetPresetValues(
                textures: [.color: .shipped, .normal: .shipped, .data: .shipped],
                maximumTextureSize: nil, mipLevels: nil, imageLimit: .lossless,
                buildMinutesOneCore: 14,
                summary: "No loss. Shipped textures. Fastest build."
            )
        case .balanced:
            AssetPresetValues(
                textures: [.color: .shipped, .normal: .astc4x4, .data: .shipped],
                maximumTextureSize: nil, mipLevels: nil,
                imageLimit: AssetImageLimit(minimumPSNR: 40, maximumNormalDegrees: 2),
                buildMinutesOneCore: 32,
                summary: "Normal maps in ASTC 4x4: less GPU memory, no visible loss."
            )
        case .bestPerformance:
            AssetPresetValues(
                textures: [.color: .astc6x6, .normal: .astc6x6, .data: .astc8x8],
                maximumTextureSize: nil, mipLevels: nil,
                imageLimit: AssetImageLimit(minimumPSNR: 30, maximumNormalDegrees: nil),
                buildMinutesOneCore: 119,
                summary: "Every texture in ASTC: least GPU memory, slight loss."
            )
        }
    }

    /// The estimated build time on a Mac with `cores` performance cores, in seconds.
    public func estimatedBuildSeconds(cores: Int) -> Double {
        values.buildMinutesOneCore * 60 / Double(max(1, cores))
    }
}
