import Foundation
@testable import opensky
import Testing

struct TimeOfDaySettingsTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "TimeOfDaySettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test
    func clearOverrideRestoresFallback() throws {
        let defaults = try makeDefaults()
        TimeOfDaySettings.store(7, to: defaults)
        TimeOfDaySettings.clearOverride(from: defaults)
        #expect(defaults.object(forKey: TimeOfDaySettings.defaultsKey) == nil)
        #expect(TimeOfDaySettings.load(from: defaults) == TimeOfDaySettings.fallback)
    }
}
