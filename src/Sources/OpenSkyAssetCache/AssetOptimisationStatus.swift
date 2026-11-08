// What the Asset Optimisation page and the Launch page say about the optimised
// files: one status, what still waits, and whether the disk has room for it.

import Foundation

nonisolated public enum AssetOptimisationStatus: Equatable, Sendable {
    case checking
    case ready
    case needsConversion(waiting: String)
    case notConverted(waiting: String)
    case converting(progress: String)

    public init(check: AssetCacheCheck?, isChecking: Bool, conversion: String?) {
        if let conversion {
            self = .converting(progress: conversion)
            return
        }
        guard let check, !isChecking else {
            self = .checking
            return
        }
        let waiting = Self.waitingLine(check)
        switch check.summary {
        case .current: self = .ready
        case .notBuilt: self = .notConverted(waiting: waiting)
        case .partlyBuilt, .stale: self = .needsConversion(waiting: waiting)
        }
    }

    public var title: String {
        switch self {
        case .checking: "Checking"
        case .ready: "Ready"
        case .needsConversion: "Needs conversion"
        case .notConverted: "Not converted"
        case .converting: "Converting"
        }
    }

    /// The SF Symbol beside the title, so the status never rests on colour alone.
    public var symbolName: String {
        switch self {
        case .checking: "clock"
        case .ready: "checkmark.circle.fill"
        case .needsConversion: "exclamationmark.triangle.fill"
        case .notConverted: "xmark.circle"
        case .converting: "arrow.triangle.2.circlepath"
        }
    }

    /// The line under the title.
    public var detail: String {
        switch self {
        case .checking: "Counting the files that wait"
        case .ready: "Every file is optimised"
        case let .needsConversion(waiting), let .notConverted(waiting): waiting
        case let .converting(progress): progress
        }
    }

    public var needsConversion: Bool {
        switch self {
        case .needsConversion, .notConverted: true
        default: false
        }
    }

    /// `41,210 base game textures, 2,003 meshes`.
    public static func waitingLine(_ check: AssetCacheCheck) -> String {
        let parts = AssetCacheKind.built.compactMap { kind -> String? in
            let pending = check.kinds[kind]?.pending ?? 0
            guard pending > 0 else { return nil }
            return "\(pending.formatted(.number.grouping(.automatic))) \(kind.noun(pending))"
        }
        guard !parts.isEmpty else { return "Nothing waits" }
        return "Waiting: base game " + parts.joined(separator: ", ")
    }
}

nonisolated extension AssetCacheKind {
    func noun(_ count: Int) -> String {
        switch self {
        case .texture: count == 1 ? "texture" : "textures"
        case .mesh: count == 1 ? "mesh" : "meshes"
        case .collision: count == 1 ? "collision model" : "collision models"
        case .animation: count == 1 ? "animation" : "animations"
        case .audio: count == 1 ? "sound" : "sounds"
        }
    }
}

/// Free space against what a conversion still writes. A conversion that does not
/// fit cannot start.
nonisolated public struct AssetSpaceCheck: Equatable, Sendable {
    public let neededBytes: UInt64
    /// Nil when the volume could not be read.
    public let volume: AssetCacheVolume?

    public init(neededBytes: UInt64, volume: AssetCacheVolume?) {
        self.neededBytes = neededBytes
        self.volume = volume
    }

    /// Output bytes are source bytes times the measured ratio of each kind.
    public init(check: AssetCacheCheck, output: AssetTextureOutput, volume: AssetCacheVolume?) {
        let needed = AssetCacheKind.built.reduce(0.0) { sum, kind in
            let source = Double(check.kinds[kind]?.pendingSourceBytes ?? 0)
            return sum + source * AssetOutputRatio.ratio(kind, output: output)
        }
        self.init(neededBytes: UInt64(needed), volume: volume)
    }

    public var fits: Bool {
        volume.map { neededBytes <= $0.availableBytes } ?? true
    }

    /// `Space: needs 3.2 GB, 120.5 GB free`.
    public var line: String {
        let free = volume.map { "\(Self.text($0.availableBytes)) free" } ?? "free space unknown"
        return "Space: needs \(Self.text(neededBytes)), \(free)"
    }

    /// The location warnings: too little space, an external disk, or a network disk.
    public var warnings: [AssetCacheLocationWarning] {
        volume.map { AssetCacheLocation.warnings(volume: $0, neededBytes: neededBytes) } ?? []
    }

    static func text(_ bytes: UInt64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

/// Optimised bytes per source byte, measured over a whole base-game conversion
/// (docs/engine/asset-cache.md, "Texture quality").
nonisolated public enum AssetOutputRatio {
    public static func ratio(_ kind: AssetCacheKind, output: AssetTextureOutput) -> Double {
        switch kind {
        case .texture: textureRatio(output.quality)
        case .mesh: 1.6
        case .collision: 0.9
        case .animation, .audio: 1
        }
    }

    static func textureRatio(_ quality: TextureQuality) -> Double {
        switch quality {
        case .original: 1.0
        case .high: 0.8
        case .medium: 0.6
        case .low: 0.45
        }
    }
}
