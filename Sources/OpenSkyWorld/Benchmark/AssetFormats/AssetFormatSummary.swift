// Totals per candidate over one asset kind (and texture role), and the
// preset rule that picks a candidate from them. Pure, so the rule is tested.

import Foundation
import OpenSkyRendering

nonisolated public struct AssetFormatGroup: Codable, Hashable, Sendable {
    public let kind: AssetKind
    public let role: TextureRole?
    public let candidate: String
    public let storage: AssetFileStorage?
    public let path: AssetLoadPath

    public var label: String {
        "\(candidate) \(storage?.rawValue ?? "archive") via \(path.rawValue)"
    }
}

nonisolated public struct AssetFormatSummary: Codable, Equatable, Sendable {
    public let group: AssetFormatGroup
    public let assetCount: Int
    public let errorCount: Int
    public let timing: AssetLoadTiming
    public let memoryBytes: Int
    public let diskBytes: Int
    /// Time to build the payloads; the one-time cost of the cache.
    public let convertMS: Double
    public let allExact: Bool
    /// The worst asset's value; nil when no asset reports one.
    public let worstRGBPSNR: Double?
    public let worstNormalAngleDegrees: Double?
    public let worstSignalToNoiseDB: Double?

    public static func summarize(_ assets: [AssetMeasurement]) -> [Self] {
        var rows: [AssetFormatGroup: [AssetCandidateMeasurement]] = [:]
        var order: [AssetFormatGroup] = []
        for asset in assets {
            for row in asset.candidates {
                let group = AssetFormatGroup(
                    kind: asset.entry.kind, role: asset.entry.role,
                    candidate: row.candidate, storage: row.storage, path: row.path
                )
                if rows[group] == nil {
                    order.append(group)
                }
                rows[group, default: []].append(row)
            }
        }
        return order.compactMap { group in rows[group].map { Self(group: group, rows: $0) } }
    }

    init(group: AssetFormatGroup, rows: [AssetCandidateMeasurement]) {
        self.group = group
        assetCount = rows.count
        errorCount = rows.count { $0.error != nil }
        timing = AssetLoadTiming(
            readMS: rows.map(\.timing.readMS).reduce(0, +),
            decodeMS: rows.map(\.timing.decodeMS).reduce(0, +),
            uploadMS: rows.map(\.timing.uploadMS).reduce(0, +)
        )
        memoryBytes = rows.map(\.memoryBytes).reduce(0, +)
        diskBytes = rows.map(\.diskBytes).reduce(0, +)
        convertMS = rows.map(\.convertMS).reduce(0, +)
        allExact = rows.allSatisfy(\.fidelity.exact)
        worstRGBPSNR = rows.compactMap { $0.fidelity.image?.rgbPSNR }.min()
        worstNormalAngleDegrees = rows.compactMap { $0.fidelity.image?.meanNormalAngleDegrees }
            .max()
        worstSignalToNoiseDB = rows.compactMap(\.fidelity.signalToNoiseDB).min()
    }
}

/// The three quality presets of the asset cache. The limits are starting values.
nonisolated public enum AssetQualityPreset: String, CaseIterable, Codable, Sendable {
    case highestQuality
    case balanced
    case bestPerformance

    /// The worst loss a preset accepts. Exact rows always pass.
    struct Limit {
        let minimumRGBPSNR: Double
        let maximumNormalAngleDegrees: Double
        let minimumSignalToNoiseDB: Double
    }

    var limit: Limit? {
        switch self {
        case .highestQuality: nil
        case .balanced: Limit(
                minimumRGBPSNR: 40, maximumNormalAngleDegrees: 2, minimumSignalToNoiseDB: 20
            )
        case .bestPerformance: Limit(
                minimumRGBPSNR: 30, maximumNormalAngleDegrees: 5, minimumSignalToNoiseDB: 10
            )
        }
    }
}

nonisolated public struct AssetFormatRecommendation: Codable, Equatable, Sendable {
    public let kind: AssetKind
    public let role: TextureRole?
    public let preset: AssetQualityPreset
    public let choice: AssetFormatGroup
    public let reason: String

    /// Highest quality: the fastest exact load. Balanced: the fastest load within
    /// the loss limit that holds no more memory than the original. Best
    /// performance: the least memory within its looser limit, then the fastest.
    public static func recommend(_ summaries: [AssetFormatSummary]) -> [Self] {
        var keys: [AssetFormatGroup] = []
        for summary in summaries where summary.group.candidate == "original" {
            keys.append(summary.group)
        }
        return keys.flatMap { key in
            let peers = summaries.filter { $0.group.kind == key.kind && $0.group.role == key.role }
            guard let original = peers.first(where: { $0.group == key }) else { return [Self]() }
            return AssetQualityPreset.allCases.compactMap { preset in
                pick(preset, from: peers, original: original)
            }
        }
    }

    private static func pick(
        _ preset: AssetQualityPreset,
        from peers: [AssetFormatSummary],
        original: AssetFormatSummary
    ) -> Self? {
        let eligible = peers.filter { summary in
            summary.errorCount == 0 && summary.assetCount == original.assetCount
                && passes(summary, preset.limit)
                && (preset != .balanced || summary.memoryBytes <= original.memoryBytes)
        }
        let best = preset == .bestPerformance
            ? eligible.min { Self.byMemory($0, $1) }
            : eligible.min { Self.bySpeed($0, $1) }
        guard let best else { return nil }
        let reason = String(
            format: "%.1f ms, %d KiB memory, %d KiB disk; original %.1f ms, %d KiB, %d KiB",
            best.timing.totalMS, best.memoryBytes / 1024, best.diskBytes / 1024,
            original.timing.totalMS, original.memoryBytes / 1024, original.diskBytes / 1024
        )
        return Self(
            kind: original.group.kind, role: original.group.role, preset: preset,
            choice: best.group, reason: reason
        )
    }

    static func passes(_ summary: AssetFormatSummary, _ limit: AssetQualityPreset.Limit?) -> Bool {
        if summary.allExact {
            return true
        }
        guard let limit else { return false }
        return (summary.worstRGBPSNR ?? .infinity) >= limit.minimumRGBPSNR
            && (summary.worstNormalAngleDegrees ?? 0) <= limit.maximumNormalAngleDegrees
            && (summary.worstSignalToNoiseDB ?? .infinity) >= limit.minimumSignalToNoiseDB
    }

    private static func byMemory(_ lhs: AssetFormatSummary, _ rhs: AssetFormatSummary) -> Bool {
        (lhs.memoryBytes, lhs.timing.totalMS) < (rhs.memoryBytes, rhs.timing.totalMS)
    }

    private static func bySpeed(_ lhs: AssetFormatSummary, _ rhs: AssetFormatSummary) -> Bool {
        (lhs.timing.totalMS, lhs.memoryBytes) < (rhs.timing.totalMS, rhs.memoryBytes)
    }
}
