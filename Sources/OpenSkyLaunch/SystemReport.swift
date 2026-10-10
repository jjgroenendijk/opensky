// The text a player copies into a problem report. It names no file path, so a
// report never shows the player's user name or folder layout.

import Foundation

nonisolated public struct SystemReport: Equatable, Sendable {
    public var macOSVersion: String
    public var chip: String
    public var gpu: String
    public var memoryGB: Double
    public var openSkyVersion: String
    public var install: GameInstallSummary?
    /// The shared benchmark's frame time, when the player ran it.
    public var benchmark: SystemReportBenchmark?

    public init(
        macOSVersion: String, chip: String, gpu: String, memoryGB: Double, openSkyVersion: String,
        install: GameInstallSummary? = nil, benchmark: SystemReportBenchmark? = nil
    ) {
        self.macOSVersion = macOSVersion
        self.chip = chip
        self.gpu = gpu
        self.memoryGB = memoryGB
        self.openSkyVersion = openSkyVersion
        self.install = install
        self.benchmark = benchmark
    }

    public var lines: [String] {
        var lines = [
            "OpenSky: \(openSkyVersion)",
            "macOS: \(macOSVersion)",
            "Chip: \(chip)",
            "GPU: \(gpu)",
            "Memory: \(Int(memoryGB.rounded())) GB",
            "Game: " + (install?.gameVersion.map { "\($0)" } ?? "unknown"),
            "DLC: " +
                (install.map { "\($0.dlc.count) of \(OfficialDLC.allCases.count)" } ?? "unknown"),
            "Creation Club plugins: " + (install.map { "\($0.creationClubPlugins)" } ?? "unknown"),
            "Mods: " + (install.map { "\($0.modPlugins) plugins" } ?? "unknown"),
            "Install problems: " + (install.map { "\($0.problems.count)" } ?? "unknown")
        ]
        lines.append("Benchmark: " + (benchmark?.line ?? "not run"))
        return lines
    }

    public var text: String {
        lines.joined(separator: "\n") + "\n"
    }
}

nonisolated public struct SystemReportBenchmark: Equatable, Sendable {
    public let averageMS: Double
    public let worstMS: Double

    public init(averageMS: Double, worstMS: Double) {
        self.averageMS = averageMS
        self.worstMS = worstMS
    }

    /// `average 8.4 ms, worst 16.9 ms`.
    public var line: String {
        String(format: "average %.1f ms, worst %.1f ms", averageMS, worstMS)
    }
}
