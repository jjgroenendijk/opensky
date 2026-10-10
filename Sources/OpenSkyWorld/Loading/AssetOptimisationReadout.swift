// The plain-word lines of the Asset Optimisation page, built from values so tests
// can pin them. Measurements: docs/engine/asset-cache.md.

import Foundation
import OpenSkyAssetCache

nonisolated public enum AssetOptimisationReadout {
    /// What direct GPU loading does now, and if it does nothing, why.
    public static func directLoadStatus(
        _ settings: AssetCacheSettings, volume: AssetCacheVolume?, status: AssetOptimisationStatus
    ) -> String {
        let load = settings.directLoad
        guard load.isEnabled else { return "Off: optimised files load through the CPU" }
        guard settings.isEnabled else { return "Inactive: asset optimisation is off" }
        guard load.textures || load.meshes else { return "Inactive: no asset type is chosen" }
        if let volume, !volume.isInternal, !load.allDisks {
            return "Inactive: the folder is on an external disk"
        }
        if case .notConverted = status {
            return "Inactive: no optimised files yet"
        }
        let kinds = [load.textures ? "textures" : nil, load.meshes ? "meshes" : nil]
            .compactMap(\.self).joined(separator: " and ")
        return "Active: \(kinds) load straight into GPU memory"
    }

    public static let directLoadReason =
        "The game archives are compressed, so Metal cannot read them directly"

    /// The measured gain and cost of each direct loading choice, in one line.
    public static let directLoadTexturesGain =
        "Textures: warm loads 12% faster, cold loads the same"
    public static let directLoadMeshesGain = "Meshes: no faster on the benchmark, so off by default"
    public static let directLoadAllDisksCost =
        "All disks: from an external disk no faster, and 377 MiB more GPU memory"

    /// `High: colour 42 dB, normals within 2°, cut-out alpha 42 dB`, or Original's line.
    public static func qualityLimitLine(_ quality: TextureQuality) -> String {
        guard let target = quality.target else {
            return "\(quality.title): the shipped blocks, unchanged"
        }
        return "\(quality.title): colour PSNR \(format(target.psnr)) dB, normals within "
            + "\(format(target.normalDegrees))°, cut-out alpha \(format(target.cutoutAlphaPSNR)) dB"
    }

    /// What each asset type is converted from and to.
    public static let conversionLines = [
        "Textures: a .dds file in a .bsa archive becomes a Metal texture with its mip levels",
        "Meshes: a .nif model becomes vertex and index buffers ready to upload",
        "Collision: a .nif collision block becomes ready physics shapes"
    ]

    public static let meshesLine = "Stored ready to use. Always identical to the game."

    /// `Needs a new conversion: 41,210 textures, about 3.2 GB`, or nil when none waits.
    public static func textureChangeLine(
        _ check: AssetCacheCheck?,
        output: AssetTextureOutput
    ) -> String? {
        guard let textures = check?.kinds[.texture], textures.pending > 0 else { return nil }
        let bytes = Double(textures.pendingSourceBytes) * AssetOutputRatio.ratio(
            .texture,
            output: output
        )
        return "Needs a new conversion: \(textures.pending.formatted()) textures, about "
            + UInt64(bytes).formatted(.byteCount(style: .file))
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
