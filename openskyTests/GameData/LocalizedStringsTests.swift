// LocalizedStrings (lstring -> table lookup through the VFS) tests. Loose
// synthetic tables in a temp data root — never extracted game files
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct LocalizedStringsTests {
    private let dataURL: URL

    init() throws {
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-lstrings-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: dataURL.appending(path: "Strings", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    private func writeTable(
        named name: String,
        kind: StringTable.Kind,
        entries: [(id: UInt32, text: String)]
    ) throws {
        try StringTableFixture.table(kind: kind, entries: entries)
            .write(to: dataURL.appending(path: "Strings/\(name)"))
    }

    private func makeStrings(language: String = "english") -> LocalizedStrings {
        LocalizedStrings(
            vfs: VirtualFileSystem(dataURL: dataURL, archiveURLs: []),
            pluginName: "Skyrim.esm",
            language: language
        )
    }

    @Test func resolvesTableIDFromMatchingKind() throws {
        try writeTable(named: "Skyrim_English.strings", kind: .strings, entries: [
            (id: 0x42, text: "Whiterun")
        ])
        try writeTable(named: "Skyrim_English.dlstrings", kind: .dlstrings, entries: [
            (id: 0x42, text: "A book text")
        ])
        let strings = makeStrings()

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

    @Test func languageSelectsTableFile() throws {
        try writeTable(named: "Skyrim_French.strings", kind: .strings, entries: [
            (id: 0x42, text: "Blancherive")
        ])
        #expect(makeStrings(language: "french").resolve(.tableID(0x42)) == "Blancherive")
        #expect(makeStrings(language: "english").resolve(.tableID(0x42)) == nil)
    }
}
