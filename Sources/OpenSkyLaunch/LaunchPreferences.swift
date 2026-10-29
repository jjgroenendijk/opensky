// A start forced by the environment skips the launcher and opens the game, and the
// environment can override the agent control setting for one launch.

import Foundation

nonisolated public enum LaunchPreferences {
    /// UI tests and `openskycli game launch` set this to `1` to start without the launcher.
    public static let environmentKey = "OPENSKY_SKIP_LAUNCHER"
    /// A forced start opens in the world unless this is `1`.
    public static let titleScreenKey = "OPENSKY_START_AT_TITLE"
    /// `1` or `0` overrides the "Agent control" setting for one launch.
    public static let agentControlKey = "OPENSKY_AGENT_CONTROL"

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

    /// Whether the app opens the agent control socket; any other value keeps `setting`.
    public static func opensAgentControl(
        setting: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        switch environment[agentControlKey] {
        case "1": true
        case "0": false
        default: setting
        }
    }
}
