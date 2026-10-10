// The game folder check over install folders built in code.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsTesting
import OpenSkyLaunch
import Testing

struct GameInstallCheckTests {
    private struct Install {
        let root: URL
        var data: URL {
            root.appending(path: "Data", directoryHint: .isDirectory)
        }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appending(
                    path: "GameInstallCheck-\(UUID().uuidString)",
                    directoryHint: .isDirectory
                )
            try FileManager.default.createDirectory(
                at: root.appending(path: "Data"), withIntermediateDirectories: true
            )
        }

        func plugin(_ name: String, records: UInt32 = 10) throws {
            try ESMFixture.tes4(recordCount: records).write(to: data.appending(path: name))
        }

        func archive(_ name: String, bytes: Data? = nil) throws {
            var fixture = BSAFixture()
            fixture.files = [.init(folder: "textures", name: "a.dds", stored: Data([1]))]
            try (bytes ?? fixture.build()).write(to: data.appending(path: name))
        }

        func executable() throws {
            try PEFixture().build().write(to: root.appending(path: "SkyrimSE.exe"))
        }

        func remove() {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: data.path
            )
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func complete() throws -> Install {
        let install = try Install()
        try install.executable()
        for name in ["Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm"] {
            try install.plugin(name)
        }
        try install.plugin("ccBGSSSE001-Fish.esm", records: 5)
        try install.plugin("ccQDRSSE001-SurvivalMode.esl", records: 5)
        try install.archive("Skyrim - Meshes0.bsa")
        try install.archive("Skyrim - Textures0.bsa")
        return install
    }

    @Test func aCompleteInstallReportsVersionDLCAndCounts() throws {
        let install = try complete()
        defer { install.remove() }
        let summary = GameInstallCheck.run(installURL: install.root)
        #expect(summary.isComplete)
        #expect(summary.gameVersion?.description == "1.6.1170.0")
        #expect(summary.dlc == [.dawnguard, .hearthfires])
        #expect(summary.creationClubPlugins == 2)
        #expect(summary.plugins == 6)
        #expect(summary.archives == 2)
        #expect(summary.records == 50)
        #expect(summary.headline == "Version 1.6.1170.0, 2 of 3 DLC, 2 Creation Club plugins")
        #expect(summary.countLine == "2 archives, 6 plugins, 50 records")
    }

    @Test func aMissingMasterIsAProblemWithAFix() throws {
        let install = try complete()
        defer { install.remove() }
        try FileManager.default.removeItem(at: install.data.appending(path: "Update.esm"))
        let summary = GameInstallCheck.run(installURL: install.root)
        #expect(summary.problems.map(\.kind) == [.missingMaster])
        #expect(summary.problems.first?.subject == "Update.esm")
        #expect(summary.problems.first?.fix.isEmpty == false)
    }

    @Test func anUnreadableArchiveIsAProblem() throws {
        let install = try complete()
        defer { install.remove() }
        try install.archive("Broken.bsa", bytes: Data("not an archive".utf8))
        let summary = GameInstallCheck.run(installURL: install.root)
        #expect(summary.problems.map(\.kind) == [.unreadableArchive])
        #expect(summary.problems.first?.subject == "Broken.bsa")
        #expect(summary.archives == 3)
    }

    @Test func anUnreadablePluginIsAProblem() throws {
        let install = try complete()
        defer { install.remove() }
        try Data("junk".utf8).write(to: install.data.appending(path: "Broken.esp"))
        let summary = GameInstallCheck.run(installURL: install.root)
        #expect(summary.problems.map(\.kind) == [.unreadablePlugin])
    }

    @Test func aFolderWithoutReadPermissionIsAProblem() throws {
        let install = try complete()
        defer { install.remove() }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: install.data.path
        )
        let summary = GameInstallCheck.run(installURL: install.root)
        #expect(summary.problems.map(\.kind) == [.unreadableFolder])
        #expect(summary.problems.first?.message == "The Data folder cannot be read")
    }

    @Test func aFolderWithoutDataSaysWhichFolderToChoose() {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "NoData-\(UUID().uuidString)")
        let summary = GameInstallCheck.run(installURL: root)
        #expect(summary.problems.map(\.kind) == [.unreadableFolder])
        #expect(summary.problems.first?.fix == "Choose the folder that holds Data/Skyrim.esm")
    }

    @Test func aMissingExecutableLeavesTheVersionUnknown() throws {
        let install = try complete()
        defer { install.remove() }
        try FileManager.default.removeItem(at: install.root.appending(path: "SkyrimSE.exe"))
        let summary = GameInstallCheck.run(installURL: install.root)
        #expect(summary.gameVersion == nil)
        #expect(summary.isComplete)
        #expect(summary.headline.hasPrefix("Version unknown"))
    }
}
