// Unit tests for GameDataLocator resolution order and fail-loud behavior.
// Fixtures are synthetic temp directories with empty marker files — never game data.

import Foundation
@testable import opensky
import Testing

struct GameDataLocatorTests {
    /// Builds a synthetic install: `<root>/Data/Skyrim.esm` (empty file).
    private func makeInstall(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "opensky-tests-\(name)-\(UUID().uuidString)")
        let data = root.appending(path: "Data")
        try FileManager.default.createDirectory(
            at: data,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: data.appending(path: "Skyrim.esm").path,
            contents: nil
        )
        return root
    }

    private func emptyDefaults() -> UserDefaults {
        let suite = "opensky-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private let missing = URL(filePath: "/nonexistent/opensky-tests", directoryHint: .isDirectory)

    @Test func environmentOverrideWins() throws {
        let install = try makeInstall(named: "env")
        defer { try? FileManager.default.removeItem(at: install) }

        let root = try GameDataLocator.locate(
            environment: [GameDataLocator.environmentKey: install.path(percentEncoded: false)],
            userDefaults: emptyDefaults(),
            defaultInstall: missing
        )
        #expect(root.source == .environment)
        #expect(root.installURL.standardizedFileURL == install.standardizedFileURL)
        #expect(root.dataURL.lastPathComponent == "Data")
    }

    @Test func overridePointingAtDataFolderIsAccepted() throws {
        let install = try makeInstall(named: "datadir")
        defer { try? FileManager.default.removeItem(at: install) }
        let data = install.appending(path: "Data")

        let root = try GameDataLocator.locate(
            environment: [GameDataLocator.environmentKey: data.path(percentEncoded: false)],
            userDefaults: emptyDefaults(),
            defaultInstall: missing
        )
        #expect(root.dataURL.standardizedFileURL == data.standardizedFileURL)
        #expect(root.installURL.standardizedFileURL == install.standardizedFileURL)
    }

    @Test func invalidEnvironmentOverrideFailsWithoutFallback() throws {
        // Valid installs exist behind both fallback sources; the bad override must
        // still fail loud instead of silently using them.
        let install = try makeInstall(named: "fallback")
        defer { try? FileManager.default.removeItem(at: install) }
        let defaults = emptyDefaults()
        defaults.set(install.path(percentEncoded: false), forKey: GameDataLocator.defaultsKey)

        #expect(throws: GameDataError.overrideInvalid(source: .environment, path: "/nope")) {
            try GameDataLocator.locate(
                environment: [GameDataLocator.environmentKey: "/nope"],
                userDefaults: defaults,
                defaultInstall: install
            )
        }
    }

    @Test func userDefaultsOverrideUsedWhenNoEnvironment() throws {
        let install = try makeInstall(named: "defaults")
        defer { try? FileManager.default.removeItem(at: install) }
        let defaults = emptyDefaults()
        defaults.set(install.path(percentEncoded: false), forKey: GameDataLocator.defaultsKey)

        let root = try GameDataLocator.locate(
            environment: [:],
            userDefaults: defaults,
            defaultInstall: missing
        )
        #expect(root.source == .userDefaults)
    }

    @Test func invalidDefaultsOverrideFailsWithoutFallback() throws {
        let install = try makeInstall(named: "steam")
        defer { try? FileManager.default.removeItem(at: install) }
        let defaults = emptyDefaults()
        defaults.set("/nope", forKey: GameDataLocator.defaultsKey)

        #expect(throws: GameDataError.overrideInvalid(source: .userDefaults, path: "/nope")) {
            try GameDataLocator.locate(
                environment: [:],
                userDefaults: defaults,
                defaultInstall: install
            )
        }
    }

    @Test func fallsBackToSteamDefaultWhenNothingConfigured() throws {
        let install = try makeInstall(named: "steamdefault")
        defer { try? FileManager.default.removeItem(at: install) }

        let root = try GameDataLocator.locate(
            environment: [:],
            userDefaults: emptyDefaults(),
            defaultInstall: install
        )
        #expect(root.source == .steamDefault)
        #expect(root.installURL == install)
    }

    @Test func nothingFoundThrowsWithSearchedPaths() {
        #expect(throws: GameDataError.notFound(searched: [missing.path(percentEncoded: false)])) {
            try GameDataLocator.locate(
                environment: [:],
                userDefaults: emptyDefaults(),
                defaultInstall: missing
            )
        }
    }

    @Test func directoryWithoutSkyrimEsmIsRejected() throws {
        // A folder that exists but holds no Data/Skyrim.esm is not an install.
        let empty = FileManager.default.temporaryDirectory
            .appending(path: "opensky-tests-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let path = empty.path(percentEncoded: false)

        #expect(throws: GameDataError.overrideInvalid(source: .environment, path: path)) {
            try GameDataLocator.locate(
                environment: [GameDataLocator.environmentKey: path],
                userDefaults: emptyDefaults(),
                defaultInstall: missing
            )
        }
    }
}
