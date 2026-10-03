// Which mode starts and whether it may start, without a real install.

import Foundation
@testable import OpenSkyGameData
import OpenSkyLaunch
import Testing

struct LaunchPreferencesTests {
    private struct MissingInstall: Error {}

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "OpenSkyLaunchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func theEnvironmentForcesAModeInAnyCase() {
        let key = LaunchPreferences.environmentKey
        #expect(LaunchPreferences.forcedMode(environment: [key: "Developer"]) == .developer)
        #expect(LaunchPreferences.forcedMode(environment: [key: "play"]) == .play)
        #expect(LaunchPreferences.forcedMode(environment: [key: "editor"]) == nil)
        #expect(LaunchPreferences.forcedMode(environment: [:]) == nil)
    }

    @Test func theLastModeDefaultsToPlayAndIsRemembered() throws {
        let defaults = try isolatedDefaults()
        #expect(LaunchPreferences.lastMode(userDefaults: defaults) == .play)
        LaunchPreferences.remember(.developer, userDefaults: defaults)
        #expect(LaunchPreferences.lastMode(userDefaults: defaults) == .developer)
    }

    @Test func playNeedsAGameFolderAndDeveloperModeDoesNot() {
        let missing = GameFolderStatus { throw MissingInstall() }
        #expect(!missing.isFound)
        #expect(!missing.canStart(.play))
        #expect(missing.canStart(.developer))

        let found = GameFolderStatus {
            GameDataRoot(
                installURL: URL(filePath: "/Games/Skyrim"),
                dataURL: URL(filePath: "/Games/Skyrim/Data"),
                source: .userDefaults
            )
        }
        #expect(found.path == "/Games/Skyrim")
        #expect(found.note == "Chosen in Settings.")
        #expect(LaunchMode.allCases.allSatisfy(found.canStart))
    }
}
