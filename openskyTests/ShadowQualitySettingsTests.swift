// World > Environment sun-shadow quality persistence (M7.1.2): rawValue store/
// load round-trips through an isolated UserDefaults suite, and any missing or
// corrupt stored value falls back to .high without crashing.

import Foundation
@testable import opensky
import Testing

struct ShadowQualitySettingsTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "ShadowQualitySettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func roundTripsEveryQuality() throws {
        let defaults = try makeDefaults()
        for quality in ShadowQuality.allCases {
            ShadowQualitySettings.store(quality, to: defaults)
            #expect(ShadowQualitySettings.load(from: defaults) == quality)
        }
    }

    @Test func missingValueFallsBackToHigh() throws {
        let defaults = try makeDefaults()
        #expect(ShadowQualitySettings.load(from: defaults) == .high)
    }

    @Test func corruptValueFallsBackToHigh() throws {
        let defaults = try makeDefaults()
        defaults.set("ultra", forKey: ShadowQualitySettings.defaultsKey)
        #expect(ShadowQualitySettings.load(from: defaults) == .high)
    }

    @Test func storesRawValueNotDescription() throws {
        let defaults = try makeDefaults()
        ShadowQualitySettings.store(.low, to: defaults)
        #expect(defaults.string(forKey: ShadowQualitySettings.defaultsKey) == "low")
    }
}
