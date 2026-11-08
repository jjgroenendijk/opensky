// Synthetic libraryfolders.vdf text, written the way Steam writes it.

import Foundation
import OpenSkyGameData
import Testing

struct SteamLibraryFoldersTests {
    private let sample = """
    "libraryfolders"
    {
    \t"0"
    \t{
    \t\t"path"\t\t"/Users/player/Library/Application Support/Steam"
    \t\t"label"\t\t""
    \t\t"apps"
    \t\t{
    \t\t}
    \t}
    \t"1"
    \t{
    \t\t"path"\t\t"/Volumes/Games/steam"
    \t\t"apps"
    \t\t{
    \t\t\t"489830"\t\t"0"
    \t\t}
    \t}
    }
    """

    @Test func readsEveryLibraryPathInOrder() {
        #expect(SteamLibraryFolders.paths(in: sample) == [
            "/Users/player/Library/Application Support/Steam",
            "/Volumes/Games/steam"
        ])
    }

    @Test func unescapesBackslashesAndQuotes() {
        let text = #"  "path"  "D:\\Steam \"Games\""  "#
        #expect(SteamLibraryFolders.paths(in: text) == [#"D:\Steam "Games""#])
    }

    @Test func skipsMalformedLines() {
        let text = """
        "path"
        "path" "/ok" "extra"
        "path" "/unterminated
        "PATH" "/upper"
        """
        #expect(SteamLibraryFolders.paths(in: text) == ["/upper"])
    }

    @Test func candidatesPointAtTheSkyrimFolderOfEachLibrary() throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "opensky-tests-vdf-\(UUID().uuidString).vdf")
        try sample.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let candidates = SteamLibraryFolders.skyrimInstallCandidates(fileURL: file)
        let skyrim = "steamapps/common/Skyrim Special Edition"
        #expect(candidates.map { $0.path(percentEncoded: false) } == [
            "/Users/player/Library/Application Support/Steam/\(skyrim)",
            "/Volumes/Games/steam/\(skyrim)"
        ])
    }

    @Test func missingFileGivesNoCandidates() {
        let file = URL(filePath: "/nonexistent/opensky-tests/libraryfolders.vdf")
        #expect(SteamLibraryFolders.skyrimInstallCandidates(fileURL: file).isEmpty)
    }
}
