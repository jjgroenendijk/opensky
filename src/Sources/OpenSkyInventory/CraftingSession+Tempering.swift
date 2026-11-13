// Tempering at a grindstone or armor table. A recipe's created object names the
// item it improves; a temper uses up the parts and raises one held copy to the best
// quality the skill reaches. See docs/engine/crafting.md.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// One quality change.
nonisolated public struct TemperStep: Equatable, Sendable {
    public let from: Int32
    public let to: Int32
}

/// The held copies a tempering recipe can improve.
nonisolated struct TemperTarget: Equatable, Sendable {
    let item: FormID
    /// The level of each held copy, highest first.
    let copies: [Int32]
    /// The best level the player's skill reaches.
    let maximum: Int32

    /// The copy a temper improves: the lowest one below the maximum.
    var from: Int32? {
        copies.filter { $0 < maximum }.min()
    }
}

extension CraftingSession {
    /// One row per recipe whose item the player holds.
    var temperStatuses: [CraftingRecipeStatus] {
        recipes.compactMap { recipe in
            guard let target = temperTarget(for: recipe) else { return nil }
            return CraftingRecipeStatus(
                recipe: recipe,
                eligibility: eligibility(of: recipe, temperingEnchanted: isEnchanted(target.item)),
                temper: target
            )
        }
    }

    func temperTarget(for recipe: CraftingRecipe) -> TemperTarget? {
        guard let item = recipe.created else { return nil }
        let held = inventory.count(of: item, in: player)
        guard held > 0 else { return nil }
        let skill = station.skill.flatMap { conditions?.skillLevel(at: $0) } ?? 0
        return TemperTarget(
            item: item,
            copies: inventory.itemCopies(of: player).levels(of: item, held: held),
            maximum: Tempering.maximumLevel(
                smithing: skill, perk: (conditions?.temperingFactor(for: item) ?? 1) - 1
            )
        )
    }

    func temper(_ recipe: CraftingRecipe) throws -> CraftOutcome {
        guard let target = temperTarget(for: recipe), let from = target.from else {
            throw CraftingError.notImprovable(recipe.id)
        }
        let verdict = eligibility(of: recipe, temperingEnchanted: isEnchanted(target.item))
        guard verdict.isEligible else { throw CraftingError.notEligible(recipe.id, verdict) }
        let consumed = consumed(by: recipe)
        try inventory.apply(removing: consumed, adding: [], on: player, usingUp: true)
        let held = inventory.count(of: target.item, in: player)
        if
            let improved = inventory.itemCopies(of: player)
                .improving(target.item, held: held, from: from, to: target.maximum)
        {
            inventory.store.set(improved, for: player.key, in: player.cell)
        }
        let value = Float(inventory.baselines.items.definition(target.item)?.value ?? 0)
        return CraftOutcome(
            consumed: consumed,
            created: InventoryStack(item: target.item, count: 1),
            experience: reportSkillUse(amount: skillUse.tempered(
                value: value, levels: Int(target.maximum - from)
            )),
            improved: TemperStep(from: from, to: target.maximum)
        )
    }

    private func isEnchanted(_ item: FormID) -> Bool {
        inventory.baselines.items.definition(item)?.enchantment != nil
    }
}
