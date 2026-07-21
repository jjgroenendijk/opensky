// Persists the World > Environment > Time of day choice (game-hours) across
// launches. Stores one Double under a UserDefaults key; a missing or
// out-of-range value falls back to 13:00 (matches Renderer.timeOfDay's own
// default) so a bad stored value never skews renderer setup. Applied when the
// renderer is (re)created (GameViewController), read + written by the
// Environment panel. Mirrors ShadowQualitySettings.

import Foundation

enum TimeOfDaySettings {
    /// UserDefaults key holding the time-of-day hour (0-24).
    static let defaultsKey = "TimeOfDaySetting"

    /// Hour used when nothing valid is stored (Renderer.timeOfDay default).
    static let fallback: Float = 13

    /// Valid game-clock range in hours.
    static let range: ClosedRange<Float> = 0 ... 24

    /// Reads the stored hour; missing/out-of-range -> fallback.
    static func load(from defaults: UserDefaults = .standard) -> Float {
        guard defaults.object(forKey: defaultsKey) != nil else { return fallback }
        let hour = Float(defaults.double(forKey: defaultsKey))
        guard hour.isFinite, range.contains(hour) else { return fallback }
        return hour
    }

    /// Persists the chosen hour, clamped into range.
    static func store(_ hour: Float, to defaults: UserDefaults = .standard) {
        let clamped = min(max(hour, range.lowerBound), range.upperBound)
        defaults.set(Double(clamped), forKey: defaultsKey)
    }
}
