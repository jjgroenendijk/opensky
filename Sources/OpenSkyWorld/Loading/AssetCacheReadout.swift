// The text the Asset Optimisation page shows, built from values so tests can pin it.

import Foundation
import OpenSkyAssetCache
import OpenSkyRendering

nonisolated public enum AssetCacheReadout {
    /// `High: no visible loss`, for the texture quality menu.
    public static func qualityTitle(_ quality: TextureQuality) -> String {
        "\(quality.title): \(quality.label.prefix(1).lowercased())\(quality.label.dropFirst())"
    }

    /// `Size: 3.2 GiB, 1200 files`.
    public static func sizeLine(_ usage: AssetCacheUsage?) -> String {
        guard let usage else { return "Size: empty" }
        return "Size: " + String(format: "%.1f", Double(usage.bytes) / Double(1 << 30))
            + " GiB, \(usage.entryCount) files"
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

    /// `Conversion: 1200 of 98000 files, about 3 min left`, or how the last one ended.
    public static func buildLine(_ progress: AssetCacheBuildProgress?, isBuilding: Bool) -> String {
        guard let progress else { return "Conversion: none" }
        if isBuilding {
            let left = progress.estimatedSecondsLeft.map { ", about \(duration($0)) left" } ?? ""
            return "Conversion: \(progress.doneFiles) of \(progress.totalFiles) files\(left)"
        }
        let outcome = progress.isCancelled ? "cancelled" : "done"
        let failed = progress.failures.count
        return "Conversion: \(outcome), \(progress.converted) converted, \(failed) failed"
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

    /// `Direct GPU loading: 412 textures, 380 MiB`, the meshes, then the last cell load.
    public static func directLoadLines(_ stats: FastTextureLoadStats) -> [String] {
        guard stats.batches > 0 || stats.externalSkips > 0 else {
            return ["Direct GPU loading: no cell loaded yet"]
        }
        var lines = [
            "Direct GPU loading: \(stats.textures) textures, \(stats.bytes >> 20) MiB",
            "Meshes: \(stats.meshes), \(stats.meshBytes >> 20) MiB",
            "Last cell: \(stats.lastBatchTextures) textures, \(stats.lastBatchMeshes) meshes, "
                + String(format: "%.0f ms", stats.lastBatchMS)
        ]
        if stats.fallbacks > 0 {
            lines.append("Fallbacks: \(stats.fallbacks) loaded on the CPU")
        }
        if stats.externalSkips > 0 {
            lines.append("External disk: \(stats.externalSkips) loaded on the CPU")
        }
        return lines
    }
}
