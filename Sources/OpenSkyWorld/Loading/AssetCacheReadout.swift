// The text the Asset Cache page shows, built from values so tests can pin it.

import Foundation
import OpenSkyAssetCache
import OpenSkyRendering

nonisolated public enum AssetCacheReadout {
    /// `Balanced: about 22 GiB, 4 min to build`.
    public static func presetTitle(_ preset: AssetQualityPreset, cores: Int) -> String {
        "\(preset.title): about \(preset.estimatedBaseGameCacheBytes >> 30) GiB, "
            + "\(duration(preset.estimatedBuildSeconds(cores: cores))) to build"
    }

    /// `Size: 3.2 GiB of 25 GiB, 1200 entries`.
    public static func sizeLine(_ usage: AssetCacheUsage?, limitBytes: UInt64) -> String {
        guard let usage else { return "Size: empty, limit \(limitBytes >> 30) GiB" }
        return "Size: " + String(format: "%.1f", Double(usage.bytes) / Double(1 << 30))
            + " GiB of \(limitBytes >> 30) GiB, \(usage.entryCount) entries"
    }

    public static func stateLine(
        _ check: AssetCacheCheck?,
        activity: AssetCacheCoordinator.Activity
    ) -> String {
        switch activity {
        case .checking: return "State: checking"
        case .clearing: return "State: clearing"
        case .building, .idle: break
        }
        guard let check else { return "State: not checked" }
        let total = check.total
        switch check.summary {
        case .current: return "State: current"
        case .notBuilt: return "State: not built"
        case .partlyBuilt: return "State: partly built, \(total.current) of \(total.total) files"
        case .stale: return "State: \(total.stale) of \(total.total) files stale"
        }
    }

    /// `Build: 1200 of 98000 files, about 3 min left` or the outcome of the last build.
    public static func buildLine(_ progress: AssetCacheBuildProgress?, isBuilding: Bool) -> String {
        guard let progress else { return "Build: none" }
        if isBuilding {
            let left = progress.estimatedSecondsLeft.map { ", about \(duration($0)) left" } ?? ""
            return "Build: \(progress.doneFiles) of \(progress.totalFiles) files\(left)"
        }
        let outcome = progress.isCancelled ? "cancelled" : "done"
        let failed = progress.failures.count
        return "Build: \(outcome), \(progress.converted) converted, \(failed) failed"
    }

    /// `Textures: 32918 entries, 4.1 GiB` for a kind's control on the cache page.
    public static func kindTitle(_ kind: AssetCacheKind, usage: AssetCacheUsage?) -> String {
        let kindUsage = usage?.kinds[kind] ?? AssetCacheKindUsage()
        return "\(kind.title): \(kindUsage.entryCount) entries, "
            + String(format: "%.1f GiB", Double(kindUsage.bytes) / Double(1 << 30))
    }

    /// The measured gain of caching `kind`, archive and cache on one disk
    /// (docs/engine/asset-cache.md, "Where the cache helps").
    public static func kindGain(_ kind: AssetCacheKind) -> String {
        switch kind {
        case .texture: "Measured: 5x faster warm, 2x faster cold"
        case .mesh: "Measured: 6x faster warm, 2x faster cold"
        case .collision: "Measured: 5x faster warm, 3x faster cold"
        case .animation, .audio: "Measured: no faster than the archives"
        }
    }

    /// Why the kinds the cache does not store have no switch.
    public static let retiredKindsNote =
        "Audio and animation load from the archives: the cache made them no faster."

    /// The fraction done, 0 to 1.
    public static func fraction(_ progress: AssetCacheBuildProgress?) -> Double {
        guard let progress, progress.totalBytes > 0 else { return 0 }
        return Double(progress.doneBytes) / Double(progress.totalBytes)
    }

    static func duration(_ seconds: Double) -> String {
        seconds < 90 ? "\(Int(seconds.rounded())) s" : "\(Int((seconds / 60).rounded())) min"
    }

    /// One line per kind that was read: `textures: 812 hits, 3 misses, 40 original, 0 stale`.
    public static func countLines(_ counts: [AssetCacheKind: AssetCacheReadCounts]) -> [String] {
        AssetCacheKind.allCases.compactMap { kind in
            guard let count = counts[kind] else { return nil }
            let stale = count.stale + count.unreadable
            return "\(kind): \(count.hits) hits, \(count.misses) misses, "
                + "\(count.original) original, \(stale) stale"
        }
    }

    /// `meshes: current, 48 KiB` per entry, or why there is none.
    public static func inspectionLines(_ entries: [AssetCacheEntryInspection]?) -> [String] {
        guard let entries else { return ["Entry: no file has this path"] }
        guard !entries.isEmpty else { return ["Entry: this file type is not cached"] }
        return entries.map { entry in
            let state = switch entry.state {
            case let .current(bytes): "current, \(max(1, bytes >> 10)) KiB"
            case .original: "loads the original"
            case let .stale(reason): "stale, \(reason)"
            case let .unreadable(reason): "unreadable, \(reason)"
            case .missing: "missing"
            }
            return "\(entry.kind): \(state)"
        }
    }

    /// `Fast load: 412 textures, 380 MiB`, then the last cell load.
    public static func fastLoadLines(_ stats: FastTextureLoadStats) -> [String] {
        guard stats.batches > 0 else { return ["Fast load: no cell loaded yet"] }
        var lines = [
            "Fast load: \(stats.textures) textures, \(stats.bytes >> 20) MiB",
            "Last cell: \(stats.lastBatchTextures) textures, \(stats.lastBatchBytes >> 20) MiB, "
                + String(format: "%.0f ms", stats.lastBatchMS)
        ]
        if stats.fallbacks > 0 {
            lines.append("Fallbacks: \(stats.fallbacks) textures loaded on the CPU")
        }
        return lines
    }
}
