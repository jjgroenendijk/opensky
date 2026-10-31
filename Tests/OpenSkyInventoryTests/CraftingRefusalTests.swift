// The notices of a refused craft or temper: missing components, perks, and skill.

import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyInventory
import Testing

struct CraftingRefusalTests {
    private static let recipe = ResolvedFormID(plugin: "Base.esm", objectID: 0x10)
    private static let short = [ComponentShortfall(item: FormID(0x20), required: 2, held: 0)]

    private static func verdict(_ function: String?, short: Bool) -> CraftingError {
        .notEligible(recipe, RecipeEligibility(
            failingFunction: function, shortfalls: short ? Self.short : [], hasUnresolvedItem: false
        ))
    }

    @Test func aForgeNamesMissingComponentsOnly() {
        #expect(CraftingRefusal.text(for: Self.verdict(nil, short: true), improving: false)
            == .lackComponentsToCreate)
        #expect(CraftingRefusal.text(for: Self.verdict("HasPerk", short: true), improving: false)
            == nil)
    }

    @Test func aTemperNamesThePerkBeforeTheComponents() {
        #expect(CraftingRefusal.text(for: Self.verdict("HasPerk", short: true), improving: true)
            == .lackPerksToImprove)
        let enchanted = Self.verdict("EPTemperingItemIsEnchanted", short: false)
        #expect(CraftingRefusal.text(for: enchanted, improving: true) == .lackMagicalPerk)
        #expect(CraftingRefusal.text(for: Self.verdict(nil, short: true), improving: true)
            == .lackComponentsToImprove)
        #expect(CraftingRefusal.text(for: .notImprovable(Self.recipe), improving: true)
            == .lackSkillToImprove)
    }

    @Test func theOutcomeLineUsesTheSettingText() {
        let line = CraftingActionOutcome.refused(.lackSkillToImprove).text(.vanilla)
        #expect(line == "You lack the required skill to improve this item")
        #expect(CraftingActionOutcome.closed.text(.vanilla) == CraftingActionOutcome.closed.text)
    }
}
