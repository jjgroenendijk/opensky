// The strings the Load Order panel and the Settings window show. They live in
// the engine so they are assertable without driving AppKit.

import Foundation
@testable import opensky
import Testing

struct PluginLoadOrderReportTests {
    private let installURL: URL
    private let dataURL: URL

    init() throws {
        installURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-report-\(UUID().uuidString)", directoryHint: .isDirectory)
        dataURL = installURL.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }

    private var root: GameDataRoot {
        GameDataRoot(installURL: installURL, dataURL: dataURL, source: .environment)
    }

    private func touch(_ names: [String]) throws {
        for name in names {
            try Data().write(to: dataURL.appending(path: name, directoryHint: .notDirectory))
        }
    }

    @Test func rowsNumberActivePluginsAndAppendMissingOnes() throws {
        try touch(["Skyrim.esm", "Mod.esp"])
        let pluginsURL = installURL.appending(path: "plugins.txt", directoryHint: .notDirectory)
        try Data("*Mod.esp\n*Gone.esp\n".utf8).write(to: pluginsURL)

        let report = PluginLoadOrderReport(resolution: PluginLoadOrder.resolve(
            root: root,
            location: .located(url: pluginsURL, source: .installFolder)
        ))

        #expect(report.rows.map(\.position) == ["1", "2", "—"])
        #expect(report.rows.map(\.name) == ["Skyrim.esm", "Mod.esp", "Gone.esp"])
        #expect(report.rows.map(\.origin) == ["Master", "plugins.txt", "plugins.txt"])
        #expect(report.rows[0].note.isEmpty)
        #expect(report.rows[2].note == "Listed active but not in Data/")
        #expect(report.summary == "2 active plugins (from plugins.txt), 1 listed but missing")
        #expect(report.pluginsTextPath == pluginsURL.path(percentEncoded: false))
        #expect(report.problem == nil)
    }

    @Test func fallbackSaysSoAndOffersTheProblemAsAPrompt() throws {
        try touch(["Skyrim.esm"])

        let report = PluginLoadOrderReport(resolution: PluginLoadOrder.resolve(
            root: root,
            location: .notFound(searched: ["/nowhere/plugins.txt"])
        ))

        #expect(report.rows.map(\.name) == ["Skyrim.esm"])
        #expect(report.summary
            == "1 active plugin (no plugins.txt found — masters and Creation Club only)")
        #expect(report.pluginsTextPath == "Not found")
        #expect(report.sourceNote.contains("/nowhere/plugins.txt"))
        #expect(report.problem?.contains("choose the file in Settings") == true)
    }

    @Test func aBadOverrideKeepsItsPathVisibleSoItCanBeCorrected() throws {
        try touch(["Skyrim.esm"])

        let report = PluginLoadOrderReport(resolution: PluginLoadOrder.resolve(
            root: root,
            location: .overrideMissing(path: "/typo/plugins.txt", source: .userDefaults)
        ))

        #expect(report.pluginsTextPath == "/typo/plugins.txt")
        #expect(report.problem?.contains("/typo/plugins.txt") == true)
    }
}
