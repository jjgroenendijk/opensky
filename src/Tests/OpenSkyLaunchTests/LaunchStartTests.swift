// Start options: parsing the saved value and remembering the last choice.

import Foundation
import OpenSkyLaunch
import Testing

struct LaunchStartTests {
    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "LaunchStartTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func storedValuesRoundTrip() {
        let starts: [LaunchStart] = [
            .normal, .cell("WhiterunBanneredMare"), .exterior(worldspace: "Tamriel", x: 6, y: -2)
        ]
        for start in starts {
            #expect(LaunchStart(storedValue: start.storedValue) == start)
        }
        #expect(LaunchStart.exterior(worldspace: "Tamriel", x: 6, y: -2).storedValue
            == "exterior:Tamriel:6:-2")
    }

    @Test func unreadableStoredValuesAreNil() {
        for text in [
            "",
            "cell:",
            "cell:Bad Name",
            "exterior:Tamriel:6",
            "exterior:Bad World:1:1",
            "exterior:Tamriel:x:1",
            "exterior:Tamriel:6:500",
            "cell: QASmoke",
            "teleport:somewhere"
        ] {
            #expect(LaunchStart(storedValue: text) == nil, "\(text)")
        }
    }

    @Test func anyWorldspaceIsAStoredStart() {
        #expect(LaunchStart(storedValue: "exterior:DLC2SolstheimWorld:7:8")
            == .exterior(worldspace: "DLC2SolstheimWorld", x: 7, y: 8))
    }

    @Test func theLastChoiceIsRemembered() throws {
        let defaults = try isolatedDefaults()
        #expect(LaunchPreferences.savedStart(userDefaults: defaults) == .normal)
        LaunchPreferences.remember(.cell("QASmoke"), userDefaults: defaults)
        #expect(LaunchPreferences.savedStart(userDefaults: defaults) == .cell("QASmoke"))
        defaults.set("garbage", forKey: LaunchPreferences.startKey)
        #expect(LaunchPreferences.savedStart(userDefaults: defaults) == .normal)
    }
}
