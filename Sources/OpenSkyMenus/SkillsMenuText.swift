// The skills menu's questions, from string settings. See docs/engine/skills-menu.md.

import OpenSkyGameData

nonisolated public enum SkillsMenuText: String, GameSettingTextKey {
    case perkConfirm = "sStatsPerkConfirm"
    /// Update.esm sets it.
    case legendaryConfirm = "sLegendaryResetConfirm"

    public var fallback: String {
        switch self {
        case .perkConfirm: "Are you sure you want this perk?"
        case .legendaryConfirm:
            "Making a skill Legendary will set it to 15 and return its perks. Are you sure?"
        }
    }
}
