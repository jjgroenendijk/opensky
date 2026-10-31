// The notices of a recipe the player cannot make or an item they cannot improve. The
// texts are string settings. See docs/engine/crafting.md#refused-crafts.

import OpenSkyGameData

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

nonisolated public enum CraftingRefusal {
    /// The condition a tempering recipe uses to ask for Arcane Blacksmith.
    static let enchantedCondition = "EPTemperingItemIsEnchanted"

    /// The notice of `error`, or nil when the game has none. A tempering recipe's
    /// failing condition is a missing perk, since its conditions are perk tests.
    public static func text(for error: CraftingError, improving: Bool) -> CraftingRefusalText? {
        switch error {
        case .unknownRecipe: nil
        case .notImprovable: .lackSkillToImprove
        case let .notEligible(_, verdict) where improving:
            switch verdict.failingFunction {
            case enchantedCondition: .lackMagicalPerk
            case .some: .lackPerksToImprove
            case nil: verdict.shortfalls.isEmpty ? nil : .lackComponentsToImprove
            }
        case let .notEligible(_, verdict):
            verdict.failingFunction == nil && !verdict.shortfalls.isEmpty
                ? .lackComponentsToCreate : nil
        }
    }
}

nonisolated extension CraftingActionOutcome {
    /// The outcome's line, with a refusal in the load order's wording.
    public func text(_ texts: GameSettingTexts<CraftingRefusalText>) -> String {
        if case let .refused(refusal) = self {
            return texts[refusal]
        }
        return text
    }
}
