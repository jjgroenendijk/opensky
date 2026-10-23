// A start forced by the environment skips the launcher and opens the game.

import Foundation

nonisolated public enum LaunchPreferences {
    /// UI tests and `openskycli game launch` set this to `1` to start without the launcher.
    public static let environmentKey = "OPENSKY_SKIP_LAUNCHER"
    /// A forced start opens in the world unless this is `1`.
    public static let titleScreenKey = "OPENSKY_START_AT_TITLE"

    public static func skipsLauncher(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[environmentKey] == "1"
    }

    public static func forcedTitleScreen(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[titleScreenKey] == "1"
    }
}
