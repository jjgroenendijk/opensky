// The skills menu's questions, from string settings. See docs/engine/skills-menu.md.

public import OpenSkyGameData

nonisolated public enum SkillsMenuText: String, GameSettingTextKey {
    case perkConfirm = "sStatsPerkConfirm"
    /// Update.esm sets it.
    case legendaryConfirm = "sLegendaryResetConfirm"
    /// Asked after a Yes to the first question.
    case legendarySecondConfirm = "sLegendaryResetSecondConfirm"

    public var fallback: String {
        switch self {
        case .perkConfirm: "Are you sure you want this perk?"
        case .legendaryConfirm:
            "Making a skill Legendary will set it to 15 and return its perks. Are you sure?"
        case .legendarySecondConfirm: "Are you sure you want to make this skill Legendary?"
        }
    }
}
