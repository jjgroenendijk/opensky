// Persists the sun-shadow quality choice (World > Environment > Sun shadows)
// across launches. Stores ShadowQuality.rawValue under one UserDefaults key; an
// absent or corrupt value falls back to `.high` so a bad stored string never
// crashes renderer setup. Applied when the renderer is (re)created
// (GameViewController), read + written by the Environment panel.

import Foundation

nonisolated public enum ShadowQualitySettings: Sendable {
    /// UserDefaults key holding the ShadowQuality rawValue string.
    public static let defaultsKey = "ShadowQualitySetting"

    /// Quality used when nothing valid is stored.
    public static let fallback = ShadowQuality.high

    /// Reads the stored quality; missing/unknown rawValue -> fallback.
    public static func load(from defaults: UserDefaults = .standard) -> ShadowQuality {
        guard
            let raw = defaults.string(forKey: defaultsKey),
            let quality = ShadowQuality(rawValue: raw)
        else {
            return fallback
        }
        return quality
    }

    /// Persists the chosen quality by rawValue.
    public static func store(_ quality: ShadowQuality, to defaults: UserDefaults = .standard) {
        defaults.set(quality.rawValue, forKey: defaultsKey)
    }

    /// Removes the explicit choice so subsequent launches use the fallback.
    public static func clearOverride(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
