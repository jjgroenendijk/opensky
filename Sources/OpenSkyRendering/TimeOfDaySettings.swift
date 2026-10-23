// Keeps the time of day (game hours) across launches. A missing or out-of-range
// value reads as 13:00, the renderer's own default, so a bad stored value never
// skews renderer setup.

import Foundation
import OpenSkyGameData

nonisolated public enum TimeOfDaySettings: Sendable {
    /// UserDefaults key holding the time-of-day hour (0-24).
    public static let defaultsKey = "TimeOfDaySetting"
    public static let key = SettingKey(defaultsKey, default: Double(fallback))

    /// Hour used when nothing valid is stored (Renderer.timeOfDay default).
    public static let fallback: Float = 13

    /// Valid game-clock range in hours.
    public static let range: ClosedRange<Float> = 0 ... 24

    /// Reads the stored hour; missing/out-of-range -> fallback.
    public static func load(
        from defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) -> Float {
        guard let stored = SettingsStore(defaults: defaults).storedValue(key) else {
            return fallback
        }
        let hour = Float(stored)
        guard hour.isFinite, range.contains(hour) else { return fallback }
        return hour
    }

    /// Persists the chosen hour, clamped into range.
    public static func store(
        _ hour: Float, to defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        let clamped = min(max(hour, range.lowerBound), range.upperBound)
        SettingsStore(defaults: defaults).set(Double(clamped), for: key)
    }

    /// Removes the explicit choice so subsequent launches use the fallback.
    public static func clearOverride(
        from defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        SettingsStore(defaults: defaults).reset(key)
    }
}
