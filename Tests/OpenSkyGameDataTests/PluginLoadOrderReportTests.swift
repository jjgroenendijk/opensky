// The strings the Load Order panel and the Settings window show. They live in
// the engine so they are assertable without driving AppKit.

import Foundation
import OpenSkyEngineTesting
@testable import OpenSkyGameData
import Testing

struct PluginLoadOrderReportTests {
    private let install: TemporaryInstall

    init() throws {
        install = try TemporaryInstall(prefix: "opensky-report")
    }

    @Test func rowsNumberActivePluginsAndAppendMissingOnes() throws {
        try install.touch(["Skyrim.esm", "Mod.esp"])
        let pluginsURL = install.installURL.appending(
            path: "plugins.txt",
            directoryHint: .notDirectory
        )
        try Data("*Mod.esp\n*Gone.esp\n".utf8).write(to: pluginsURL)

        let report = PluginLoadOrderReport(resolution: PluginLoadOrder.resolve(
            root: install.root,
            location: .located(url: pluginsURL, source: .installFolder)
        ))

        #expect(report.rows.map(\.index) == ["00", "01", "—"])
        #expect(report.rows.map(\.name) == ["Skyrim.esm", "Mod.esp", "Gone.esp"])
        #expect(report.rows.map(\.origin) == ["Master", "plugins.txt", "plugins.txt"])
        #expect(report.rows[0].note.isEmpty)
        #expect(report.rows[2].note == "Listed active but not in Data/")
        #expect(report.summary == "2 active plugins (from plugins.txt), 1 listed but missing")
        #expect(report.pluginsTextPath == pluginsURL.path(percentEncoded: false))
        #expect(report.problem == nil)
    }

    @Test func lightPluginsShowTheirFESlot() throws {
        try install.touch(["Skyrim.esm", "Small.esl", "Mod.esp"])
        var header = Data("TES4".utf8)
        header += [0, 0, 0, 0, 0x00, 0x02, 0, 0]
        try header.write(to: install.dataURL.appending(path: "Flagged.esp"))
        let pluginsURL = install.installURL.appending(path: "plugins.txt")
        try Data("*Small.esl\n*Mod.esp\n*Flagged.esp\n".utf8).write(to: pluginsURL)

        let resolution = PluginLoadOrder.resolve(
            root: install.root,
            location: .located(url: pluginsURL, source: .installFolder)
        )
        let report = PluginLoadOrderReport(resolution: resolution)

        #expect(resolution.entries.map(\.isLight) == [false, true, false, true])
        #expect(report.rows.map(\.index) == ["00", "FE 000", "01", "FE 001"])
    }

    @Test func fallbackSaysSoAndOffersTheProblemAsAPrompt() throws {
        try install.touch(["Skyrim.esm"])

        let report = PluginLoadOrderReport(resolution: PluginLoadOrder.resolve(
            root: install.root,
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
        try install.touch(["Skyrim.esm"])

        let report = PluginLoadOrderReport(resolution: PluginLoadOrder.resolve(
            root: install.root,
            location: .overrideMissing(path: "/typo/plugins.txt", source: .userDefaults)
        ))

        #expect(report.pluginsTextPath == "/typo/plugins.txt")
        #expect(report.problem?.contains("/typo/plugins.txt") == true)
    }
}
