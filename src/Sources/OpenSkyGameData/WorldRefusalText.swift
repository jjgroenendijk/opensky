// The HUD notices of a place the player cannot go. See docs/engine/walk-mode.md.

nonisolated public enum WorldRefusalText: String, GameSettingTextKey {
    case leavingBorderRegion = "sPlayerLeavingBorderRegion"

    public var fallback: String {
        switch self {
        case .leavingBorderRegion: "You cannot go that way."
        }
    }
}
