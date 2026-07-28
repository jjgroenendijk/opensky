// Active-plugin ordering from synthetic empty install entries and text lists.

import Foundation
@testable import opensky
import Testing

struct PluginLoadOrderTests {
    @Test
    func officialCreationClubAndStarredPluginsResolveInPriorityOrder() throws {
        let install = FileManager.default.temporaryDirectory
            .appending(path: "opensky-plugins-\(UUID().uuidString)", directoryHint: .isDirectory)
        let data = install.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        for name in ["Skyrim.esm", "Update.esm", "Club.esl", "Active.esp", "Inactive.esp"] {
            try Data().write(to: data.appending(path: name))
        }
        try Data("Club.esl\nMissing.esl\n".utf8).write(
            to: install.appending(path: "Skyrim.ccc")
        )
        let plugins = install.appending(path: "plugins.txt")
        try Data("# comment\nInactive.esp\n*ACTIVE.ESP\n*Missing.esp\n".utf8).write(to: plugins)
        let root = GameDataRoot(installURL: install, dataURL: data, source: .environment)

        let result = PluginLoadOrder.resolve(root: root, pluginsTextURL: plugins)

        #expect(result.map(\.name) == ["Skyrim.esm", "Update.esm", "Club.esl", "Active.esp"])
    }
}
