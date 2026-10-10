// The Diagnostics page's system report, from fake system values: every line, the
// unknown install, and no file path.

import Foundation
import OpenSkyFormatsCore
import OpenSkyLaunch
import Testing

struct SystemReportTests {
    private func install() -> GameInstallSummary {
        var summary = GameInstallSummary()
        summary.gameVersion = PEFileVersion(1, 6, 1170, 0)
        summary.dlc = [.dawnguard, .hearthfires, .dragonborn]
        summary.creationClubPlugins = 4
        summary.plugins = 12
        return summary
    }

    @Test func theReportListsTheSystemTheGameAndTheBenchmark() {
        let report = SystemReport(
            macOSVersion: "26.1", chip: "Apple M1", gpu: "Apple M1", memoryGB: 16,
            openSkyVersion: "0.34 (1234)", install: install(),
            benchmark: SystemReportBenchmark(averageMS: 8.42, worstMS: 16.91)
        )
        #expect(report.text == """
        OpenSky: 0.34 (1234)
        macOS: 26.1
        Chip: Apple M1
        GPU: Apple M1
        Memory: 16 GB
        Game: 1.6.1170.0
        DLC: 3 of 3
        Creation Club plugins: 4
        Mods: 3 plugins
        Install problems: 0
        Benchmark: average 8.4 ms, worst 16.9 ms

        """)
    }

    @Test func withoutAnInstallOrABenchmarkTheLinesSaySo() {
        let report = SystemReport(
            macOSVersion: "26.1", chip: "Apple M1", gpu: "Apple M1", memoryGB: 15.6,
            openSkyVersion: "0.34"
        )
        #expect(report.lines.contains("Game: unknown"))
        #expect(report.lines.contains("Mods: unknown"))
        #expect(report.lines.contains("Memory: 16 GB"))
        #expect(report.lines.last == "Benchmark: not run")
        #expect(!report.text.contains("/"))
    }

    @Test func aLogLineNamesItsTimeAndCategory() {
        let date = Date(timeIntervalSince1970: 1_791_838_344)
        #expect(SessionLogExport.line(date: date, category: "CellStream", message: "loaded")
            == "\(date.ISO8601Format()) [CellStream] loaded")
    }
}
