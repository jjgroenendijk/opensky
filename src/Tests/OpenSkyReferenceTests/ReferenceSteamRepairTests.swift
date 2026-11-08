// The wrapper swap, the browser lock purge, and the prefix write guard, on a
// temporary prefix.

import Foundation
@testable import OpenSkyReference
import Testing

struct ReferenceSteamRepairTests {
    private func makePrefix() throws -> ReferencePrefix {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ReferenceSteamRepairTests-\(UUID())", directoryHint: .isDirectory)
        let prefix = ReferencePrefix(root: root)
        try FileManager.default.createDirectory(
            at: prefix.webHelperWrapper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("wrapper".utf8).write(to: prefix.webHelperWrapper)
        return prefix
    }

    @Test func wrapperReplacesOnlyValvesLargeHelper() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix.root) }
        let files = FileManager.default
        for (folder, size) in [("cef.win64", 600_000), ("cef.win7x64", 10)] {
            let directory = prefix.cefDirectory.appending(path: folder, directoryHint: .isDirectory)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(count: size).write(to: directory.appending(path: "steamwebhelper.exe"))
        }
        #expect(try ReferenceSteamRepair.deployWrapper(prefix: prefix) == 1)
        let win64 = prefix.cefDirectory.appending(path: "cef.win64")
        let helper = try Data(contentsOf: win64.appending(path: "steamwebhelper.exe"))
        let real = try Data(contentsOf: win64.appending(path: "steamwebhelper_real.exe"))
        #expect(helper == Data("wrapper".utf8))
        #expect(real.count == 600_000)
        #expect(try ReferenceSteamRepair.deployWrapper(prefix: prefix) == 0)
    }

    @Test func missingWrapperThrows() {
        let prefix = ReferencePrefix(root: URL(filePath: "/nonexistent/prefix"))
        #expect(throws: ReferenceLauncherError.noWrapper) {
            try ReferenceSteamRepair.deployWrapper(prefix: prefix)
        }
    }

    @Test func locksGoAndOtherFilesStay() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix.root) }
        let cache = prefix.driveC.appending(path: "users/jj/AppData/Local/Steam/htmlcache")
        let nested = cache.appending(path: "Default", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        for file in [
            cache.appending(path: "SingletonLock"),
            nested.appending(path: "LOCK.lock"),
            cache.appending(path: "Cookies")
        ] {
            try Data().write(to: file)
        }
        #expect(ReferenceSteamRepair.removeBrowserLocks(prefix: prefix) == 2)
        #expect(FileManager.default.fileExists(atPath: cache.appending(path: "Cookies").path()))
    }

    @Test func writesThroughALinkOutOfThePrefixAreRefused() throws {
        let prefix = try makePrefix()
        let outside = prefix.root.deletingLastPathComponent()
            .appending(path: "outside-\(UUID())", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: prefix.root)
            try? FileManager.default.removeItem(at: outside)
        }
        let user = prefix.driveC.appending(path: "users/jj", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: user.appending(path: "Documents"), withDestinationURL: outside
        )
        let games = user.appending(path: "Documents/My Games/Skyrim Special Edition")
        #expect(throws: ReferenceLauncherError.self) {
            try ReferenceLauncher.requireInsidePrefix(games, prefix: prefix)
        }
        let saved = user.appending(path: "Saved Games/x")
        try ReferenceLauncher.requireInsidePrefix(saved, prefix: prefix)
    }
}
