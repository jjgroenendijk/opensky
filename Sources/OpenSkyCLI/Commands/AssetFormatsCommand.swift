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
        let comparison = try AssetFormatComparison(
            files: files,
            storedSize: { files.storedByteCount(forPath: $0) },
            device: device,
            library: Renderer.makeBundledShaderLibrary(device: device),
            scratch: URL(fileURLWithPath: scratchPath),
            plan: AssetFormatComparisonPlan(
                entries: standard.entries.filter { kind == nil || $0.kind == kind },
                repeats: standard.repeats
            )
        )
        comparison.progress = { print("[INFO] measuring \($0)") }
        let result = comparison.run(machine: .current(gpu: device.name))
        report(result)
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
}
