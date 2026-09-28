// Active-plugin ordering from synthetic empty install trees and text lists.
// Fixtures are marker files — never real game data (AGENTS.md "Legal & IP").

import Foundation
@testable import opensky
import Testing

struct PluginLoadOrderTests {
    private let installURL: URL
    private let dataURL: URL

    init() throws {
        installURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-plugins-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    /// Writes the file and returns the location the resolver would produce for
    /// it, so a test names its own fixture instead of relying on the search.
    @discardableResult
    private func writePluginsText(_ text: String) throws -> PluginsTextLocation {
        let url = installURL.appending(path: "plugins.txt", directoryHint: .notDirectory)
        try Data(text.utf8).write(to: url)
        return .located(url: url, source: .installFolder)
    }

    private func writeCreationClub(_ text: String) throws {
        try Data(text.utf8).write(
            to: installURL.appending(path: "Skyrim.ccc", directoryHint: .notDirectory)
        )
    }

    @Test func officialCreationClubAndStarredPluginsResolveInPriorityOrder() throws {
        try touch(["Skyrim.esm", "Update.esm", "Club.esl", "Active.esp", "Inactive.esp"])
        try writeCreationClub("Club.esl\nMissing.esl\n")
        let location = try writePluginsText(
            "# comment\nInactive.esp\n*ACTIVE.ESP\n*Missing.esp\n"
        )

        let result = PluginLoadOrder.resolve(root: root, location: location)

        #expect(result.entries.map(\.name) == [
            "Skyrim.esm", "Update.esm", "Club.esl", "Active.esp"
        ])
        #expect(result.entries.map(\.origin) == [
            .implicitMaster, .implicitMaster, .creationClub, .pluginsText
        ])
        #expect(result.isVanillaFallback == false)
    }

    /// The order plugins.txt lists mods in is the order they load in — the
    /// whole point of reading the file rather than sorting names.
    @Test func starredEntriesKeepFileOrderNotAlphabeticalOrder() throws {
        try touch(["Skyrim.esm", "Zebra.esp", "Alpha.esp", "Middle.esp"])
        let location = try writePluginsText("*Zebra.esp\n*Middle.esp\n*Alpha.esp\n")

        let result = PluginLoadOrder.resolve(root: root, location: location)

        #expect(result.entries.map(\.name) == [
            "Skyrim.esm", "Zebra.esp", "Middle.esp", "Alpha.esp"
        ])
    }

    /// An unstarred line is a plugin the user switched off in the launcher.
    @Test func unstarredAndNonPluginLinesAreNotActive() throws {
        try touch(["Skyrim.esm", "Off.esp", "On.esp", "Notes.txt"])
        let location = try writePluginsText("Off.esp\n*On.esp\n*Notes.txt\n\n   \n")

        let result = PluginLoadOrder.resolve(root: root, location: location)

        #expect(result.entries.map(\.name) == ["Skyrim.esm", "On.esp"])
    }

    @Test func missingPluginsTextFallsBackToTheOfficialMastersOnDisk() throws {
        try touch(["Skyrim.esm", "Dawnguard.esm", "NotListed.esp"])

        let result = PluginLoadOrder.resolve(
            root: root,
            location: .notFound(searched: ["/nowhere/plugins.txt"])
        )

        #expect(result.entries.map(\.name) == ["Skyrim.esm", "Dawnguard.esm"])
        #expect(result.isVanillaFallback)
        #expect(result.missing.isEmpty)
    }

    /// Only a plugins.txt entry is worth reporting as missing. A DLC the user
    /// does not own is a normal install, and Skyrim.ccc catalogues everything
    /// Creation Club sells rather than what is installed.
    @Test func onlyPluginsTextEntriesAreReportedMissing() throws {
        try touch(["Skyrim.esm"])
        try writeCreationClub("ccGone.esl\n")
        let location = try writePluginsText("*Gone.esp\n")

        let result = PluginLoadOrder.resolve(root: root, location: location)

        #expect(result.entries.map(\.name) == ["Skyrim.esm"])
        #expect(result.missing == [
            PluginLoadOrder.MissingPlugin(name: "Gone.esp", origin: .pluginsText)
        ])
    }

    /// plugins.txt spells names however the launcher wrote them; the engine
    /// opens the file the case-insensitive volume actually holds.
    @Test func entriesCarryTheOnDiskSpelling() throws {
        try touch(["Skyrim.esm", "MixedCase.esp"])
        let location = try writePluginsText("*mixedcase.esp\n")

        let result = PluginLoadOrder.resolve(root: root, location: location)

        #expect(result.entries.map(\.name) == ["Skyrim.esm", "MixedCase.esp"])
        #expect(result.entries.last?.url.lastPathComponent == "MixedCase.esp")
    }

    /// A master starred in plugins.txt keeps its pinned position rather than
    /// loading twice or moving after the mods.
    @Test func mastersListedInPluginsTextDeduplicateAgainstThePinnedOrder() throws {
        try touch(["Skyrim.esm", "Update.esm", "Mod.esp"])
        let location = try writePluginsText("*Mod.esp\n*Update.esm\n*Skyrim.esm\n")

        let result = PluginLoadOrder.resolve(root: root, location: location)

        #expect(result.entries.map(\.name) == ["Skyrim.esm", "Update.esm", "Mod.esp"])
    }
}
