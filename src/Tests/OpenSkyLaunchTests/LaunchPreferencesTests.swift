// Whether the launcher is skipped, and whether the game folder lets Play start,
// without a real install.

import Foundation
@testable import OpenSkyGameData
import OpenSkyLaunch
import Testing

struct LaunchPreferencesTests {
    private struct MissingInstall: Error {}

    @Test func onlyOneSkipsTheLauncher() {
        let key = LaunchPreferences.environmentKey
        #expect(LaunchPreferences.skipsLauncher(environment: [key: "1"]))
        #expect(!LaunchPreferences.skipsLauncher(environment: [key: "0"]))
        #expect(!LaunchPreferences.skipsLauncher(environment: [key: "play"]))
        #expect(!LaunchPreferences.skipsLauncher(environment: [:]))
    }

    @Test func aForcedLaunchOpensAtTheTitleOnlyWhenAsked() {
        let key = LaunchPreferences.titleScreenKey
        #expect(LaunchPreferences.forcedTitleScreen(environment: [key: "1"]))
        #expect(!LaunchPreferences.forcedTitleScreen(environment: [key: "0"]))
        #expect(!LaunchPreferences.forcedTitleScreen(environment: [:]))
    }

    @Test func theEnvironmentOverridesTheAgentControlSetting() {
        let key = LaunchPreferences.agentControlKey
        #expect(LaunchPreferences.opensAgentControl(setting: false, environment: [key: "1"]))
        #expect(!LaunchPreferences.opensAgentControl(setting: true, environment: [key: "0"]))
        #expect(LaunchPreferences.opensAgentControl(setting: true, environment: [:]))
        #expect(!LaunchPreferences.opensAgentControl(setting: false, environment: [key: "yes"]))
    }

    @Test func theGameFolderIsFoundOnlyWhenTheInstallLocates() {
        let missing = GameFolderStatus { throw MissingInstall() }
        #expect(!missing.isFound)

        let found = GameFolderStatus {
            GameDataRoot(
                installURL: URL(filePath: "/Games/Skyrim"),
                dataURL: URL(filePath: "/Games/Skyrim/Data"),
                source: .userDefaults
            )
        }
        #expect(found.isFound)
        #expect(found.path == "/Games/Skyrim")
        #expect(found.note == "Chosen in Settings.")
    }
}
