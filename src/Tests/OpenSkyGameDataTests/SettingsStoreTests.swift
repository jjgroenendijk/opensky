// SettingsStore: typed reads with defaults, override state, reset, and migration.

import Foundation
@testable import OpenSkyGameData
import Testing

struct SettingsStoreTests {
    static let flag = SettingKey("SettingsStoreTestsFlag", default: true)
    static let hour = SettingKey("SettingsStoreTestsHour", default: 13.0)

    func freshDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: "opensky.tests.\(name)"))
        defaults.removePersistentDomain(forName: "opensky.tests.\(name)")
        return defaults
    }

    @Test func aMissingValueReadsAsTheDefault() throws {
        let store = try SettingsStore(defaults: freshDefaults("missing"))
        #expect(store.value(Self.flag))
        #expect(store.storedValue(Self.hour) == nil)
        #expect(!store.isOverridden(Self.hour))
    }

    @Test func aStoredValueIsOverriddenUntilReset() throws {
        let store = try SettingsStore(defaults: freshDefaults("stored"))
        store.set(false, for: Self.flag)
        #expect(!store.value(Self.flag))
        #expect(store.isOverridden(Self.flag))
        store.reset(Self.flag)
        #expect(store.value(Self.flag))
    }

    @Test func migrationMovesOnlyMissingValues() throws {
        let old = try freshDefaults("old")
        let store = try SettingsStore(defaults: freshDefaults("new"))
        old.set(6.0, forKey: Self.hour.name)
        old.set(false, forKey: Self.flag.name)
        store.set(true, for: Self.flag)
        store.migrate([Self.hour.name, Self.flag.name], from: old)
        #expect(store.value(Self.hour) == 6)
        #expect(store.value(Self.flag))
        #expect(old.object(forKey: Self.hour.name) == nil)
    }
}
