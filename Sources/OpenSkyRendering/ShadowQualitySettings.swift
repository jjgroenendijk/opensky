// Persists the sun-shadow quality choice (World > Environment > Sun shadows)
// across launches. Stores ShadowQuality.rawValue in the shared settings domain; an
// absent or corrupt value falls back to `.high` so a bad stored string never
// crashes renderer setup. Applied when the renderer is (re)created
// (GameViewController), read + written by the Environment panel.

import Foundation
import OpenSkyGameData

nonisolated public enum ShadowQualitySettings: Sendable {
    /// UserDefaults key holding the ShadowQuality rawValue string.
    public static let defaultsKey = "ShadowQualitySetting"
    public static let key = SettingKey(defaultsKey, default: fallback.rawValue)

    /// Quality used when nothing valid is stored.
    public static let fallback = ShadowQuality.high

    /// Reads the stored quality; missing/unknown rawValue -> fallback.
    public static func load(
        from defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) -> ShadowQuality {
        ShadowQuality(rawValue: SettingsStore(defaults: defaults).value(key)) ?? fallback
    }

    /// Persists the chosen quality by rawValue.
    public static func store(
        _ quality: ShadowQuality, to defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        SettingsStore(defaults: defaults).set(quality.rawValue, for: key)
    }

    /// Removes the explicit choice so subsequent launches use the fallback.
    public static func clearOverride(
        from defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        SettingsStore(defaults: defaults).reset(key)
    }
}
