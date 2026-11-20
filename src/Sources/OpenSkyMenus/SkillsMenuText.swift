// The skills menu's questions, from string settings. See docs/engine/skills-menu.md.

public import OpenSkyGameData

nonisolated public enum SkillsMenuText: String, GameSettingTextKey {
    case perkConfirm = "sStatsPerkConfirm"
    /// Update.esm sets it.
    case legendaryConfirm = "sLegendaryResetConfirm"
    /// Asked after a Yes to the first question.
    case legendarySecondConfirm = "sLegendaryResetSecondConfirm"
    /// `%s` is Health, Magicka, or Stamina.
    case attributeConfirm = "sConfirmAttribute"
    /// The buttons of the three questions: yes, and cancel in place of no.
    case yes = "sYesText"
    case cancel = "sCancel"
    /// The attribute question's yes button.
    case ok = "sOk"

    public var fallback: String {
        switch self {
        case .perkConfirm: "Are you sure you want this perk?"
        case .legendaryConfirm:
            "Making a skill Legendary will set it to 15 and return its perks. Are you sure?"
        case .legendarySecondConfirm: "Are you sure you want to make this skill Legendary?"
        case .attributeConfirm: "Increase %s?"
        case .ok: "Ok"
        case .yes: "Yes"
        case .cancel: "Cancel"
        }
    }
}
