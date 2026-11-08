public import OpenSkyGameData

nonisolated public enum CraftingRefusalText: String, GameSettingTextKey {
    case lackComponentsToCreate = "sLackRequiredToCreate"
    case lackComponentsToImprove = "sLackRequiredToImprove"
    case lackPerksToImprove = "sLackRequiredPerksToImprove"
    case lackMagicalPerk = "sLackRequiredPerkToImproveMagical"
    case lackSkillToImprove = "sLackRequiredSkillToImprove"

    public var fallback: String {
        switch self {
        case .lackComponentsToCreate: "You lack the required components to create this item"
        case .lackComponentsToImprove: "You lack the required components to improve this item"
        case .lackPerksToImprove: "You lack the required perks to improve this item"
        case .lackMagicalPerk: "You lack the perk to improve magical items"
        case .lackSkillToImprove: "You lack the required skill to improve this item"
        }
    }
}
