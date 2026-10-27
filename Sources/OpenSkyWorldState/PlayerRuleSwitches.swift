// Session rules a script switches for the player. Kept on the player's delta so the
// save carries them in the `PRUL` chunk. See docs/engine/papyrus-session-natives.md.

import OpenSkyFormatsESM

/// `Debug.SetGodMode` and `Game.SetPlayerReportCrime`.
nonisolated public struct PlayerRuleSwitches: WorldStateComponent, Hashable, Sendable {
    /// The player takes no damage.
    public var godMode: Bool
    /// Witnesses report the player's crimes. Off, a crime costs the player nothing.
    public var reportsCrime: Bool

    public static let standard = Self()

    public static var componentKind: WorldStateComponentKind {
        .playerRules
    }

    public init(godMode: Bool = false, reportsCrime: Bool = true) {
        self.godMode = godMode
        self.reportsCrime = reportsCrime
    }
}

nonisolated extension WorldStateComponentKind {
    public static let playerRules = Self(
        rawValue: "playerRules", order: 45, affectsCellBuild: false
    )
}

extension WorldStateStore {
    /// The player's switches; the standard ones when no script changed them.
    public var playerRules: PlayerRuleSwitches {
        get { component(PlayerRuleSwitches.self, for: .player) ?? .standard }
        set {
            if newValue == .standard {
                reset(.playerRules, for: .player)
            } else {
                set(newValue, for: .player)
            }
        }
    }
}
