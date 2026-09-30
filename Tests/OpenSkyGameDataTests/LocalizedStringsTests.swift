// LocalizedStrings (lstring -> table lookup through the VFS) tests. Synthetic
// tables in an in-memory file source — never extracted game files
// (AGENTS.md "Legal & IP boundary").

import FormatsCoreTesting
import Foundation
import GameDataTesting
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
}
