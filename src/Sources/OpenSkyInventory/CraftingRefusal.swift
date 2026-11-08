// The notices of a recipe the player cannot make or an item they cannot improve. The
// texts are string settings. See docs/engine/crafting.md#refused-crafts.

public import OpenSkyGameData
public import OpenSkyInventoryInterface

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
