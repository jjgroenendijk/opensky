// Env-gated sweep of the user's own Skyrim saves: every save decodes, and the newest
// imports against the install. Saves are read-only; only counts are asserted.
// Set OPENSKY_SKYRIM_SAVES to the saves folder (docs/engine/ess-import.md).

import Foundation
import OpenSkyFormatsESS
@testable import OpenSkyGameData
import OpenSkySave
import TagsTesting
import Testing

@Suite(.tags(.smoke))
struct ESSRealDataTests {
    private static let folder: URL? = ESSSaveFolderSetting.folder(userDefaults: nil)

    private static var hasSaves: Bool {
        guard case .ready = ESSSaveFolder.status(of: folder) else { return false }
        return true
    }

    @Test(.enabled(if: hasSaves))
    func everySaveDecodes() throws {
        let folder = try #require(Self.folder)
        for url in try ESSSaveFolder(directory: folder).saveURLs() {
            let file = try ESSFile(data: Data(contentsOf: url, options: .mappedIfSafe))
            let survey = ESSChangeFormSurvey(file.changeForms)
            #expect(!file.plugins.isEmpty, "\(url.lastPathComponent) lists no plugins")
            #expect(survey.types.reduce(0) { $0 + $1.count } == file.changeForms.count)
            #expect((try? file.papyrus()) != nil, "\(url.lastPathComponent) Papyrus table")
        }
    }

    @Test(.enabled(if: hasSaves && RealDataEnvironment.hasDataRoot))
    func theNewestSaveImports() async throws {
        let folder = try #require(Self.folder)
        let root = try #require(RealDataEnvironment.dataRoot)
        let newest = try #require(try ESSSaveFolder(directory: folder).listings().first)
        let file = try await ESSSaveFolder.readFile(at: newest.url)
        let index = await ESSPluginIndex.load(for: file, root: root)
        let result = ESSImporter.run(
            file,
            records: ESSPluginRecords(index: index),
            appVersion: "test"
        )
        #expect(result.report.category("player")?.imported ?? 0 > 0)
        #expect(result.report.category("globals")?.imported ?? 0 > 0)
        #expect(result.contents.clock != nil)
        #expect(result.placement != nil)
    }
}
