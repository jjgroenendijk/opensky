// Active-plugin order from empty synthetic install trees and text lists.

import EngineTesting
import Foundation
@testable import OpenSkyGameData
import Testing

struct PluginLoadOrderTests {
    private let install: TemporaryInstall

    init() throws {
        install = try TemporaryInstall(prefix: "opensky-plugins")
    }

    /// Writes the file and returns the location the resolver would produce for
    /// it, so a test names its own fixture instead of relying on the search.
    @discardableResult
    private func writePluginsText(_ text: String) throws -> PluginsTextLocation {
        let url = install.installURL.appending(path: "plugins.txt", directoryHint: .notDirectory)
        try Data(text.utf8).write(to: url)
        return .located(url: url, source: .installFolder)
    }

    private func writeCreationClub(_ text: String) throws {
        try Data(text.utf8).write(
            to: install.installURL.appending(path: "Skyrim.ccc", directoryHint: .notDirectory)
        )
    }

    @Test func officialCreationClubAndStarredPluginsResolveInPriorityOrder() throws {
        try install.touch(["Skyrim.esm", "Update.esm", "Club.esl", "Active.esp", "Inactive.esp"])
        try writeCreationClub("Club.esl\nMissing.esl\n")
        let location = try writePluginsText(
            "# comment\nInactive.esp\n*ACTIVE.ESP\n*Missing.esp\n"
        )

        let result = PluginLoadOrder.resolve(root: install.root, location: location)

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
        try install.touch(["Skyrim.esm", "Zebra.esp", "Alpha.esp", "Middle.esp"])
        let location = try writePluginsText("*Zebra.esp\n*Middle.esp\n*Alpha.esp\n")

        let result = PluginLoadOrder.resolve(root: install.root, location: location)

        #expect(result.entries.map(\.name) == [
            "Skyrim.esm", "Zebra.esp", "Middle.esp", "Alpha.esp"
        ])
    }

    /// An unstarred line is a plugin the user switched off in the launcher.
    @Test func unstarredAndNonPluginLinesAreNotActive() throws {
        try install.touch(["Skyrim.esm", "Off.esp", "On.esp", "Notes.txt"])
        let location = try writePluginsText("Off.esp\n*On.esp\n*Notes.txt\n\n   \n")

        let result = PluginLoadOrder.resolve(root: install.root, location: location)

        #expect(result.entries.map(\.name) == ["Skyrim.esm", "On.esp"])
    }

    @Test func missingPluginsTextFallsBackToTheOfficialMastersOnDisk() throws {
        try install.touch(["Skyrim.esm", "Dawnguard.esm", "NotListed.esp"])

        let result = PluginLoadOrder.resolve(
            root: install.root,
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
        try install.touch(["Skyrim.esm"])
        try writeCreationClub("ccGone.esl\n")
        let location = try writePluginsText("*Gone.esp\n")

        let result = PluginLoadOrder.resolve(root: install.root, location: location)

        #expect(result.entries.map(\.name) == ["Skyrim.esm"])
        #expect(result.missing == [
            PluginLoadOrder.MissingPlugin(name: "Gone.esp", origin: .pluginsText)
        ])
    }

    /// plugins.txt spells names however the launcher wrote them; the engine
    /// opens the file the case-insensitive volume actually holds.
    @Test func entriesCarryTheOnDiskSpelling() throws {
        try install.touch(["Skyrim.esm", "MixedCase.esp"])
        let location = try writePluginsText("*mixedcase.esp\n")

        let result = PluginLoadOrder.resolve(root: install.root, location: location)

        #expect(result.entries.map(\.name) == ["Skyrim.esm", "MixedCase.esp"])
        #expect(result.entries.last?.url.lastPathComponent == "MixedCase.esp")
    }

    /// A master starred in plugins.txt keeps its pinned position rather than
    /// loading twice or moving after the mods.
    @Test func mastersListedInPluginsTextDeduplicateAgainstThePinnedOrder() throws {
        try install.touch(["Skyrim.esm", "Update.esm", "Mod.esp"])
        let location = try writePluginsText("*Mod.esp\n*Update.esm\n*Skyrim.esm\n")

        let result = PluginLoadOrder.resolve(root: install.root, location: location)

        #expect(result.entries.map(\.name) == ["Skyrim.esm", "Update.esm", "Mod.esp"])
    }
}
