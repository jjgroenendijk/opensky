// The text summary of a tour result, and the files a run writes.

import Foundation

nonisolated public enum BenchmarkReport {
    public static let resultFile = "result.json"
    public static let summaryFile = "summary.txt"

    public static func lines(for result: BenchmarkTourResult) -> [String] {
        var lines = [
            "OpenSky benchmark: \(result.preset.title), "
                +
                "\(result.frameWidth)x\(result.frameHeight), \(format(result.durationSeconds)) s" +
                (result.stopped ? " (stopped)" : "")
        ]
        if !result.overrides.isEmpty {
            let pairs = result.overrides.sorted { $0.key < $1.key }
                .map { "\($0.key)=\(format($0.value))" }
            lines.append("Overrides: " + pairs.joined(separator: ", "))
        }
        if let start = result.appStart {
            let process = start.processToWorldReadyMS
                .map { ", process start to world ready \(format($0)) ms" } ?? ""
            lines.append("App start: world load \(format(start.worldLoadMS)) ms\(process)")
        }
        for (name, pass) in [("Cold load", result.coldLoad), ("Warm load", result.warmLoad)] {
            guard let pass else { continue }
            lines.append("\(name): \(format(pass.totalMS)) ms over \(pass.cells.count) builds")
        }
        if let frame = result.frameTime {
            lines.append("All scenes: " + describe(frame))
        }
        lines.append("")
        lines += result.scenes.map(sceneLine)
        return lines
    }

    static func sceneLine(_ scene: BenchmarkSceneResult) -> String {
        let name = scene.title.padding(toLength: 24, withPad: " ", startingAt: 0)
        switch scene.status {
        case .skipped:
            return "\(name) skipped: \(scene.note ?? "")"
        case .failed:
            return "\(name) [ERROR] \(scene.note ?? "failed")"
        case .measured:
            var parts = scene.frameTime.map { [describe($0)] } ?? []
            if let gpu = scene.gpuTime {
                parts.append("GPU avg \(format(gpu.averageMS)) ms")
            }
            if let slowest = scene.slowestPass {
                parts.append("slowest pass \(slowest.name) \(format(slowest.averageMS)) ms")
            }
            if let arrival = scene.arrivalMS {
                parts.append("arrival \(format(arrival / 1000)) s")
            }
            if let note = scene.note {
                parts.append("[WARNING] \(note)")
            }
            return "\(name) " + parts.joined(separator: ", ")
        }
    }

    static func describe(_ frame: BenchmarkDistribution) -> String {
        "\(format(frame.averageFPS)) fps avg, 1% low \(format(frame.onePercentLowFPS)) fps, "
            + "p95 \(format(frame.percentile95MS)) ms, worst \(format(frame.worstMS)) ms"
    }

    static func format(_ value: Double) -> String {
        String(format: value >= 100 ? "%.0f" : "%.1f", value)
    }

    /// Writes `result.json` and `summary.txt` into `folder`, creating it.
    public static func write(_ result: BenchmarkTourResult, to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try result.jsonData().write(to: folder.appending(path: resultFile), options: .atomic)
        let text = lines(for: result).joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: folder.appending(path: summaryFile), options: .atomic)
    }

    /// `~/Library/Application Support/OpenSky/Benchmarks/`.
    public static var defaultParent: URL {
        URL.applicationSupportDirectory.appending(
            path: "OpenSky/Benchmarks",
            directoryHint: .isDirectory
        )
    }

    /// `<defaultParent>/<UTC>/`, for a run started without `--out`.
    public static func defaultFolder(startedAt date: Date) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let stamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "")
        return defaultParent.appending(path: "\(stamp)Z", directoryHint: .isDirectory)
    }

    /// The newest run folder under `parent` that holds a readable result.
    public static func latestRun(in parent: URL = defaultParent)
        -> (folder: URL, result: BenchmarkTourResult)?
    {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            if
                let data = try? Data(contentsOf: folder.appending(path: resultFile)),
                let result = try? BenchmarkTourResult.decode(json: data)
            {
                return (folder, result)
            }
        }
        return nil
    }
}
