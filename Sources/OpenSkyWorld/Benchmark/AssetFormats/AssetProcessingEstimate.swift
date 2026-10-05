// The time and disk space to convert the whole install to one candidate, scaled
// from the sample by work units (docs/tools/asset-format-comparison.md).

import Foundation
import OpenSkyRendering

nonisolated public struct AssetProcessingEstimate: Codable, Equatable, Sendable {
    public let kind: AssetKind
    public let role: TextureRole?
    public let candidate: String
    public let storage: AssetFileStorage?
    public let fileCount: Int
    /// On one core: the archive read, the conversion, and the cache write.
    public let processingMS: Double
    public let diskBytes: Int

    /// One estimate per candidate and storage that every sampled asset of a
    /// census bucket measured without an error.
    public static func estimate(assets: [AssetMeasurement], census: AssetCensus) -> [Self] {
        census.buckets.flatMap { bucket in
            let sample = assets.filter {
                $0.entry.kind == bucket.kind && $0.entry.role == bucket.role
                    && $0.error == nil && $0.workUnits > 0
            }
            return estimates(bucket, sample)
        }
    }

    private static func estimates(
        _ bucket: AssetCensusBucket,
        _ sample: [AssetMeasurement]
    ) -> [Self] {
        let sampleUnits = Double(sample.map(\.workUnits).reduce(0, +))
        guard sampleUnits > 0 else { return [] }
        let scale = Double(bucket.workUnits) / sampleUnits
        var costs: [String: (ms: Double, disk: Int)] = [:]
        var counts: [String: Int] = [:]
        var order: [(candidate: String, storage: AssetFileStorage?)] = []
        for asset in sample {
            let readMS = asset.candidates.first { $0.candidate == "original" }?.timing.readMS ?? 0
            var seen: Set<String> = []
            for row in asset.candidates where row.candidate != "original" && row.error == nil {
                let key = "\(row.candidate)/\(row.storage?.rawValue ?? "")"
                guard seen.insert(key).inserted else { continue }
                if costs[key] == nil {
                    order.append((row.candidate, row.storage))
                }
                let cost = costs[key] ?? (0, 0)
                costs[key] = (
                    cost.ms + readMS + row.convertMS + row.writeMS,
                    cost.disk + row.diskBytes
                )
                counts[key, default: 0] += 1
            }
        }
        return order.compactMap { candidate, storage in
            let key = "\(candidate)/\(storage?.rawValue ?? "")"
            guard counts[key] == sample.count, let cost = costs[key] else { return nil }
            return Self(
                kind: bucket.kind, role: bucket.role, candidate: candidate, storage: storage,
                fileCount: bucket.fileCount, processingMS: cost.ms * scale,
                diskBytes: Int(Double(cost.disk) * scale)
            )
        }
    }

    /// The whole install converted as one preset picks: time on one core and
    /// the cache size. A pick of the original costs nothing.
    public static func total(
        _ preset: AssetQualityPreset,
        recommendations: [AssetFormatRecommendation],
        estimates: [Self]
    ) -> (processingMS: Double, diskBytes: Int) {
        var processingMS = 0.0
        var diskBytes = 0
        for pick in recommendations where pick.preset == preset {
            let choice = pick.choice
            guard
                let estimate = estimates.first(where: {
                    $0.kind == choice.kind && $0.role == choice.role
                        && $0.candidate == choice.candidate && $0.storage == choice.storage
                }) else { continue }
            processingMS += estimate.processingMS
            diskBytes += estimate.diskBytes
        }
        return (processingMS, diskBytes)
    }
}
