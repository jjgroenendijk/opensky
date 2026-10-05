// LocalizedStrings (lstring -> table lookup through the VFS) tests. Synthetic
// tables in an in-memory file source — never extracted game files
// (AGENTS.md "Legal & IP boundary").

import EngineTesting
import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct LocalizedStringsTests {
    private func makeStrings(
        _ files: InMemoryFileSource = InMemoryFileSource(),
        language: String = "english"
    ) -> LocalizedStrings {
        LocalizedStrings(
            vfs: files,
            pluginName: "Skyrim.esm",
            language: language
        )
    }

    @Test func resolvesTableIDFromMatchingKind() {
        let strings = makeStrings(InMemoryFileSource(files: [
            "Strings/Skyrim_English.strings": StringTableFixture.table(
                kind: .strings, entries: [(id: 0x42, text: "Whiterun")]
            ),
            "Strings/Skyrim_English.dlstrings": StringTableFixture.table(
                kind: .dlstrings, entries: [(id: 0x42, text: "A book text")]
            )
        ]))

        #expect(strings.resolve(.tableID(0x42)) == "Whiterun")
        #expect(strings.resolve(.tableID(0x42), kind: .dlstrings) == "A book text")
        #expect(strings.resolve(.tableID(0x99)) == nil)
    }

    @Test func inlineTextPassesThrough() {
        let strings = makeStrings()
        #expect(strings.resolve(.inline("Breezehome")) == "Breezehome")
        #expect(strings.resolve(nil) == nil)
    }

    @Test func missingTableYieldsNilNotError() {
        let strings = makeStrings()
        #expect(strings.resolve(.tableID(0x42)) == nil)
        // Second lookup exercises the cached .failed slot.
        #expect(strings.resolve(.tableID(0x42)) == nil)
    }

    @Test func languageSelectsTableFile() {
        let files = InMemoryFileSource(files: [
            "Strings/Skyrim_French.strings": StringTableFixture.table(
                kind: .strings, entries: [(id: 0x42, text: "Blancherive")]
            )
        ])
        #expect(makeStrings(files, language: "french").resolve(.tableID(0x42)) == "Blancherive")
        #expect(makeStrings(files, language: "english").resolve(.tableID(0x42)) == nil)
    }

    /// A string ID belongs to the plugin that wrote the record. Two plugins may
    /// use the same ID for different text.
    @Test func scopedTablesKeepTwoPluginsApart() {
        let strings = makeStrings(InMemoryFileSource(files: [
            "Strings/Skyrim_English.strings": StringTableFixture.table(
                kind: .strings, entries: [(id: 0x42, text: "Whiterun")]
            ),
            "Strings/Dawnguard_English.strings": StringTableFixture.table(
                kind: .strings, entries: [(id: 0x42, text: "Fort Dawnguard")]
            )
        ]))
        let dawnguard = strings.scoped(to: "Dawnguard.esm")

        #expect(strings.resolve(.tableID(0x42)) == "Whiterun")
        #expect(dawnguard.resolve(.tableID(0x42)) == "Fort Dawnguard")
        #expect(dawnguard.pluginName == "Dawnguard.esm")
        #expect(strings.scoped(to: "skyrim.esm") === strings)
        #expect(strings.scoped(to: "Missing.esm").resolve(.tableID(0x42)) == nil)
    }
}
