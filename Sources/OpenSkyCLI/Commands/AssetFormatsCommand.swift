// `asset-formats`: the asset format comparison on the real install. Prints a
// summary and the recommendations, and writes the stable JSON result
// (docs/tools/asset-format-comparison.md).

import Foundation
import Metal
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld

enum AssetFormatsCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let outPath = try scanner.option("--out")
        let scratchPath = try scanner.option("--scratch")
        let kindName = try scanner.option("--kind")
        try scanner.finish()
        guard let scratchPath else { throw CLIError.failure("--scratch <dir> is required") }
        let kind = try kindName.map { name in
            guard let kind = AssetKind(rawValue: name) else {
                throw CLIError.failure("unknown --kind \(name)")
            }
            return kind
        }
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            throw CLIError.failure("no Metal 4 GPU available")
        }
        let files = context.makeFileSystem()
        let standard = AssetFormatComparisonPlan.standard
        let plan = AssetFormatComparisonPlan(
            entries: standard.entries.filter { kind == nil || $0.kind == kind },
            repeats: standard.repeats
        )
        let comparison = try AssetFormatComparison(
            files: files,
            storedSize: { files.storedByteCount(forPath: $0) },
            device: device,
            library: Renderer.makeBundledShaderLibrary(device: device),
            scratch: URL(fileURLWithPath: scratchPath),
            plan: plan
        )
        print("[INFO] counting the install")
        let census = AssetCensus.count(
            files: files,
            storedSize: { files.storedByteCount(forPath: $0) },
            kinds: Set(plan.entries.map(\.kind))
        )
        comparison.progress = { print("[INFO] measuring \($0)") }
        let result = comparison.run(machine: .current(gpu: device.name), census: census)
        report(result)
        reportEstimates(result)
        if let outPath {
            let url = URL(fileURLWithPath: outPath)
            try result.jsonData().write(to: url)
            print("[INFO] wrote result -> \(url.path(percentEncoded: false))")
        }
        guard result.isComparable else {
            throw CLIError.failure("an asset failed to load; this result does not compare")
        }
    }

    private static func report(_ result: AssetFormatComparisonResult) {
        let machine = result.machine
        print(
            "[INFO] machine: \(machine.modelIdentifier), \(machine.cpu), \(machine.gpu); "
                + "build \(result.buildConfiguration.rawValue); load average "
                + result.loadAverage.map { String(format: "%.1f", $0) }.joined(separator: " -> ")
        )
        print(
            "[INFO] started \(result.startedAt.ISO8601Format()); \(result.plan.entries.count) "
                + "assets, median of \(result.plan.repeats) loads"
        )
        for asset in result.assets {
            let status = asset.error.map { " [ERROR] \($0)" } ?? ""
            let failed = asset.candidates.filter { $0.error != nil }
            print("[INFO] \(asset.entry.path): \(asset.detail)\(status)")
            for row in failed {
                print("[WARNING]   \(row.candidate) \(row.storage?.rawValue ?? "") "
                    + "\(row.path.rawValue): \(row.error ?? "")")
            }
        }
        for summary in result.summaries {
            let group = summary.group
            print(String(
                format: "[INFO] %@%@ %@: %.1f ms, %d KiB memory, %d KiB disk, %.0f ms convert%@",
                group.kind.rawValue, group.role.map { "/\($0.rawValue)" } ?? "", group.label,
                summary.timing.totalMS, summary.memoryBytes / 1024, summary.diskBytes / 1024,
                summary.convertMS, fidelityText(summary)
            ))
        }
        for pick in result.recommendations {
            print("[OK] \(pick.kind.rawValue)\(pick.role.map { "/\($0.rawValue)" } ?? "") "
                + "\(pick.preset.rawValue): \(pick.choice.label) (\(pick.reason))")
        }
    }

    private static func fidelityText(_ summary: AssetFormatSummary) -> String {
        if summary.allExact {
            return ", exact"
        }
        var parts: [String] = []
        if let psnr = summary.worstRGBPSNR {
            parts.append(String(format: "worst %.1f dB", psnr))
        }
        if let angle = summary.worstNormalAngleDegrees {
            parts.append(String(format: "worst %.2f deg normals", angle))
        }
        if let noise = summary.worstSignalToNoiseDB {
            parts.append(String(format: "worst SNR %.1f dB", noise))
        }
        return parts.isEmpty ? ", lossy" : ", " + parts.joined(separator: ", ")
    }

    private static func reportEstimates(_ result: AssetFormatComparisonResult) {
        for bucket in result.census?.buckets ?? [] {
            let role = bucket.role.map { "/\($0.rawValue)" } ?? ""
            print(
                "[INFO] install \(bucket.kind.rawValue)\(role): "
                    + "\(bucket.fileCount) files, \(bucket.storedBytes >> 20) MiB stored, "
                    + "\(bucket.unreadableCount) unreadable"
            )
        }
        for estimate in result.estimates {
            print(
                "[INFO] whole game \(estimate.kind.rawValue)"
                    + "\(estimate.role.map { "/\($0.rawValue)" } ?? "") \(estimate.candidate) "
                    + "\(estimate.storage?.rawValue ?? ""): \(duration(estimate.processingMS)) "
                    + "on one core, \(estimate.diskBytes >> 20) MiB cache"
            )
        }
        let cores = ProcessInfo.processInfo.activeProcessorCount
        for preset in AssetQualityPreset.allCases where !result.estimates.isEmpty {
            let total = AssetProcessingEstimate.total(
                preset, recommendations: result.recommendations, estimates: result.estimates
            )
            print(
                "[OK] whole game \(preset.rawValue): \(duration(total.processingMS)) on one core, "
                    + "at best \(duration(total.processingMS / Double(cores))) on \(cores) cores, "
                    + "\(total.diskBytes >> 20) MiB cache"
            )
        }
    }

    private static func duration(_ milliseconds: Double) -> String {
        let seconds = Int(milliseconds / 1000)
        if seconds >= 3600 {
            return "\(seconds / 3600) h \(seconds % 3600 / 60) min"
        }
        return seconds >= 60 ? "\(seconds / 60) min \(seconds % 60) s" : "\(seconds) s"
    }
}
