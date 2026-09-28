// LocalizedLabels tests: the pure merge/fallback core over synthetic
// TranslationFile values, and the VFS discovery loader over a temp data root
// with loose files plus a synthetic BSA — never extracted game files (AGENTS.md
// "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct LocalizedLabelsTests {
    private func table(_ pairs: [(key: String, value: String)]) throws -> TranslationFile {
        try TranslationFile(data: TranslationFileFixture.file(pairs))
    }

    @Test func resolvesKnownKey() throws {
        let labels = try LocalizedLabels(
            language: "english",
            files: [table([(key: "$ExitGame", value: "Quit")])]
        )
        #expect(labels.label(for: "$ExitGame") == "Quit")
        #expect(labels.value(forKey: "$ExitGame") == "Quit")
        #expect(labels.keyCount == 1)
        #expect(labels.fileCount == 1)
    }

    @Test func unknownKeyFallsBackToToken() throws {
        let labels = try LocalizedLabels(language: "english", files: [table([])])
        #expect(labels.label(for: "$Missing") == "$Missing")
        #expect(labels.value(forKey: "$Missing") == nil)
    }

    @Test func nonTokenPassesThrough() {
        let labels = LocalizedLabels(language: "english", files: [])
        #expect(labels.label(for: "Plain text") == "Plain text")
        #expect(labels.label(for: "").isEmpty)
    }

    @Test func mergeAcrossFilesLastWins() throws {
        let labels = try LocalizedLabels(language: "english", files: [
            table([(key: "$A", value: "base"), (key: "$Shared", value: "old")]),
            table([(key: "$B", value: "extra"), (key: "$Shared", value: "new")])
        ])
        #expect(labels.fileCount == 2)
        #expect(labels.keyCount == 3)
        #expect(labels.label(for: "$A") == "base")
        #expect(labels.label(for: "$B") == "extra")
        #expect(labels.label(for: "$Shared") == "new")
    }

    // MARK: - VFS discovery

    private func makeDataRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-labels-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeLoose(_ relativePath: String, _ data: Data, under dataURL: URL) throws {
        let url = dataURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    @Test func loadMergesLooseAndArchiveForLanguage() throws {
        let dataURL = try makeDataRoot()
        // Loose file under Interface/Translations (mod-style override location).
        try writeLoose(
            "Interface/Translations/MyMod_English.txt",
            TranslationFileFixture.file([(key: "$Mod", value: "loose value")]),
            under: dataURL
        )
        // Same language in an archive, plus an off-language file that must be
        // ignored, plus an unrelated archive path outside the directory.
        var fixture = BSAFixture()
        fixture.files = [
            .init(
                folder: "interface\\translations",
                name: "base_english.txt",
                stored: TranslationFileFixture.file([(key: "$Base", value: "archived value")])
            ),
            .init(
                folder: "interface\\translations",
                name: "base_french.txt",
                stored: TranslationFileFixture.file([(key: "$Base", value: "valeur")])
            ),
            .init(
                folder: "interface",
                name: "note.txt",
                stored: TranslationFileFixture.file([(key: "$Nope", value: "x")])
            )
        ]
        let archiveURL = dataURL.appending(path: "base.bsa", directoryHint: .notDirectory)
        try fixture.build().write(to: archiveURL)

        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [archiveURL])
        let labels = LocalizedLabels.load(vfs: vfs, language: "english")

        #expect(labels.fileCount == 2)
        #expect(labels.label(for: "$Mod") == "loose value")
        #expect(labels.label(for: "$Base") == "archived value")
        // French file was not for the requested language.
        #expect(labels.value(forKey: "$Base") != "valeur")
    }

    @Test func loadToleratesMalformedFile() throws {
        let dataURL = try makeDataRoot()
        try writeLoose(
            "Interface/Translations/good_english.txt",
            TranslationFileFixture.file([(key: "$Ok", value: "fine")]),
            under: dataURL
        )
        // Lone high surrogate -> not valid UTF-16; must be skipped, not fatal.
        var broken = TranslationFileFixture.file([(key: "$Bad", value: "x")])
        broken.append(contentsOf: [0x00, 0xD8])
        try writeLoose("Interface/Translations/bad_english.txt", broken, under: dataURL)

        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let labels = LocalizedLabels.load(vfs: vfs, language: "english")

        #expect(labels.label(for: "$Ok") == "fine")
        #expect(labels.value(forKey: "$Bad") == nil)
    }

    @Test func loadWithNoTranslationsIsEmpty() throws {
        let dataURL = try makeDataRoot()
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let labels = LocalizedLabels.load(vfs: vfs, language: "english")
        #expect(labels.fileCount == 0)
        #expect(labels.keyCount == 0)
        #expect(labels.label(for: "$Anything") == "$Anything")
    }
}
