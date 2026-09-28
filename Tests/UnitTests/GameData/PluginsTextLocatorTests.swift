// Finding plugins.txt across the layouts a macOS install can take. Every
// fixture is a synthetic temp tree; the real home directory is never consulted
// (the test host withholds it, and each test injects its own).

import Foundation
@testable import opensky
import Testing

struct PluginsTextLocatorTests {
    private let libraryURL: URL
    private let installURL: URL
    private let dataURL: URL
    private let homeURL: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appending(
                path: "opensky-pluginstext-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        // Mirrors a Steam library: <library>/steamapps/common/<game>.
        libraryURL = base.appending(path: "steamapps", directoryHint: .isDirectory)
        installURL = libraryURL
            .appending(path: "common", directoryHint: .isDirectory)
            .appending(path: "Skyrim Special Edition", directoryHint: .isDirectory)
        dataURL = installURL.appending(path: "Data", directoryHint: .isDirectory)
        homeURL = base.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    }

    private var root: GameDataRoot {
        GameDataRoot(installURL: installURL, dataURL: dataURL, source: .environment)
    }

    @discardableResult
    private func writeFile(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("*Mod.esp\n".utf8).write(to: url)
        return url
    }

    private func locate(environment: [String: String] = [:]) -> PluginsTextLocation {
        PluginsTextLocator.locate(
            root: root,
            environment: environment,
            userDefaults: nil,
            home: homeURL
        )
    }

    @Test func environmentOverrideWins() throws {
        let chosen = try writeFile(at: homeURL.appending(path: "elsewhere/plugins.txt"))
        try writeFile(at: installURL.appending(path: "plugins.txt"))

        let located = locate(environment: [
            PluginsTextLocator.environmentKey: chosen.path(percentEncoded: false)
        ])

        #expect(located == .located(url: chosen, source: .environment))
    }

    /// A configured path that is not there is a mistake to report, not a
    /// reason to quietly load a different load order.
    @Test func missingOverrideIsReportedRatherThanFallingThrough() throws {
        try writeFile(at: installURL.appending(path: "plugins.txt"))

        let located = locate(environment: [
            PluginsTextLocator.environmentKey: "/nowhere/plugins.txt"
        ])

        #expect(located == .overrideMissing(path: "/nowhere/plugins.txt", source: .environment))
        #expect(located.url == nil)
        #expect(located.problemDescription != nil)
    }

    @Test func installFolderBeatsApplicationSupport() throws {
        let install = try writeFile(at: installURL.appending(path: "plugins.txt"))
        try writeFile(at: homeURL.appending(
            path: "Library/Application Support/Skyrim Special Edition/plugins.txt"
        ))

        #expect(locate() == .located(url: install, source: .installFolder))
    }

    @Test func applicationSupportIsFoundWhenTheInstallFolderHasNone() throws {
        let support = try writeFile(at: homeURL.appending(
            path: "Library/Application Support/Skyrim Special Edition/plugins.txt"
        ))

        #expect(locate() == .located(url: support, source: .applicationSupport))
    }

    /// The game only writes plugins.txt into its Windows per-user folder, so
    /// on this platform it usually lives inside a compatibility prefix.
    @Test func steamCompatibilityPrefixIsSearched() throws {
        let prefixed = try writeFile(at: libraryURL
            .appending(path: "compatdata/\(PluginsTextLocator.steamAppID)/pfx")
            .appending(path: "drive_c/users/steamuser/AppData/Local")
            .appending(path: "Skyrim Special Edition/plugins.txt"))

        #expect(locate() == .located(url: prefixed, source: .windowsPrefix))
    }

    @Test func crossOverBottleIsSearchedAndPublicProfileSkipped() throws {
        let bottle = homeURL
            .appending(path: "Library/Application Support/CrossOver/Bottles/Skyrim")
            .appending(path: "drive_c/users")
        try writeFile(at: bottle.appending(
            path: "Public/AppData/Local/Skyrim Special Edition/plugins.txt"
        ))
        let real = try writeFile(at: bottle.appending(
            path: "crossover/AppData/Local/Skyrim Special Edition/plugins.txt"
        ))

        #expect(locate() == .located(url: real, source: .windowsPrefix))
    }

    @Test func nothingFoundListsWhatWasSearched() {
        let located = locate()

        guard case let .notFound(searched) = located else {
            Issue.record("expected notFound, got \(located)")
            return
        }
        #expect(searched.contains { $0.hasSuffix("Skyrim Special Edition/plugins.txt") })
        #expect(located.problemDescription != nil)
    }

    @Test func savingAnUnreadableChoiceThrowsAndLeavesTheSettingAlone() throws {
        let defaults = try #require(UserDefaults(suiteName: "opensky-tests-\(UUID().uuidString)"))

        #expect(throws: PluginsTextError.self) {
            try PluginsTextLocator.saveUserChoice(
                path: "/nowhere/plugins.txt",
                userDefaults: defaults
            )
        }
        #expect(defaults.string(forKey: PluginsTextLocator.defaultsKey) == nil)
    }

    @Test func savedChoiceIsUsedUntilItIsCleared() throws {
        let defaults = try #require(UserDefaults(suiteName: "opensky-tests-\(UUID().uuidString)"))
        let chosen = try writeFile(at: homeURL.appending(path: "chosen/plugins.txt"))

        try PluginsTextLocator.saveUserChoice(
            path: chosen.path(percentEncoded: false),
            userDefaults: defaults
        )
        let located = PluginsTextLocator.locate(
            root: root,
            environment: [:],
            userDefaults: defaults,
            home: homeURL
        )
        #expect(located == .located(url: chosen, source: .userDefaults))

        PluginsTextLocator.clearUserChoice(userDefaults: defaults)
        #expect(defaults.string(forKey: PluginsTextLocator.defaultsKey) == nil)
    }

    /// A unit test must not pick up the developer's own load order — the same
    /// rule `GameDataLocator` follows for the data root (issue #362).
    @Test func hostWithholdsThePersistentSources() {
        #expect(GameDataLocator.isRunningInTestHost)
        #expect(PluginsTextLocator.persistedDefaults == nil)
        #expect(PluginsTextLocator.homeCandidate == nil)
    }
}
