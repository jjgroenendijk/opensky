// Which mode starts: a mode forced by the environment skips the launcher,
// otherwise the launcher offers the mode the user picked last.

import Foundation

nonisolated public enum LaunchPreferences {
    /// UI tests and scripts set this to start a mode without the launcher.
    public static let environmentKey = "OPENSKY_LAUNCH_MODE"
    public static let lastModeKey = "OpenSkyLastLaunchMode"
    /// A forced mode opens in the world unless this is `1`.
    public static let titleScreenKey = "OPENSKY_START_AT_TITLE"

    public static func forcedMode(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LaunchMode? {
        environment[environmentKey].flatMap { LaunchMode(rawValue: $0.lowercased()) }
    }

    public static func forcedTitleScreen(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[titleScreenKey] == "1"
    }

    public static func lastMode(userDefaults: UserDefaults = .standard) -> LaunchMode {
        userDefaults.string(forKey: lastModeKey).flatMap(LaunchMode.init(rawValue:)) ?? .play
    }

    public static func remember(_ mode: LaunchMode, userDefaults: UserDefaults = .standard) {
        userDefaults.set(mode.rawValue, forKey: lastModeKey)
    }
}
