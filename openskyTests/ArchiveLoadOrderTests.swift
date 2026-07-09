// Unit tests for archive load-order resolution. Fixtures: temp install trees
// with empty marker files — never real game data (AGENTS.md "Legal & IP").

import Foundation
@testable import opensky
import Testing

struct ArchiveLoadOrderTests {
    private let installURL: URL
    private let dataURL: URL

    init() throws {
        installURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-order-\(UUID().uuidString)", directoryHint: .isDirectory)
        dataURL = installURL.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }

    /// Existence markers only — load order never reads file contents.
    private func touch(_ names: [String]) throws {
        for name in names {
            try Data().write(to: dataURL.appending(path: name, directoryHint: .notDirectory))
        }
    }

    private func writeIni(_ name: String, list1: String, list2: String) throws {
        let text = """
        [Archive]
        sResourceArchiveList=\(list1)
        sResourceArchiveList2=\(list2)
        """
        try Data(text.utf8).write(to: installURL.appending(path: name))
    }

    private func resolvedNames() -> [String] {
        ArchiveLoadOrder.resolve(installURL: installURL, dataURL: dataURL)
            .map(\.lastPathComponent)
    }

    @Test func iniListsFirstThenPluginArchivesOfficialsBeforeOthers() throws {
        try writeIni(
            "Skyrim_Default.ini",
            list1: "Skyrim - Misc.bsa, Skyrim - Absent.bsa",
            list2: "Skyrim - Textures0.bsa"
        )
        try touch([
            "Skyrim - Misc.bsa", "Skyrim - Textures0.bsa",
            "Skyrim.esm", "Update.esm", "BMod.esp", "AMod.esp",
            "BMod.bsa", "AMod.bsa", "AMod - Textures.bsa"
        ])

        // Absent ini archive skipped; official plugins have no archives here;
        // remaining plugins alphabetical, .bsa before " - Textures.bsa".
        #expect(resolvedNames() == [
            "Skyrim - Misc.bsa", "Skyrim - Textures0.bsa",
            "AMod.bsa", "AMod - Textures.bsa", "BMod.bsa"
        ])
    }

    @Test func skyrimIniOverridesShippedDefaultIni() throws {
        try writeIni("Skyrim_Default.ini", list1: "Default.bsa", list2: "")
        try writeIni("Skyrim.ini", list1: "User.bsa", list2: "")
        try touch(["Default.bsa", "User.bsa"])

        #expect(resolvedNames() == ["User.bsa"])
    }

    @Test func missingIniFallsBackToVanillaListFilteredToDisk() throws {
        try touch(["Skyrim - Misc.bsa", "Skyrim - Textures3.bsa", "Unrelated.bsa"])

        // Vanilla list order, only what exists; Unrelated.bsa has no plugin.
        #expect(resolvedNames() == ["Skyrim - Misc.bsa", "Skyrim - Textures3.bsa"])
    }

    @Test func officialPluginArchivesPrecedeOtherPluginArchives() throws {
        try writeIni("Skyrim_Default.ini", list1: "", list2: "")
        try touch([
            "AAA.esp", "AAA.bsa",
            "Dragonborn.esm", "Dragonborn.bsa",
            "Skyrim.esm", "Skyrim.bsa"
        ])

        #expect(resolvedNames() == ["Skyrim.bsa", "Dragonborn.bsa", "AAA.bsa"])
    }

    @Test func duplicatesAndCaseDifferencesResolveOnce() throws {
        try writeIni("Skyrim_Default.ini", list1: "MYMOD.BSA", list2: "MyMod.bsa")
        try touch(["MyMod.esp", "MyMod.bsa"])

        // Ini claims it twice (case-varied); plugin rule would add it again.
        #expect(resolvedNames() == ["MyMod.bsa"])
    }
}
