// Main-app crafting and harvest seam: the open station's recipes with their
// verdicts, the station list, and the crosshair plant. AppKit-free.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyWorldInterface

extension InventoryCoordinator.CraftingReadout {
    public var craftingSnapshot: CraftingControlSnapshot {
        guard coordinator.runtime != nil else { return .unavailable }
        return CraftingControlSnapshot(
            stationName: coordinator.crafting?.interaction.name,
            recipes: coordinator.crafting?.statuses.map(recipeReadout) ?? []
        )
    }

    private func recipeReadout(_ status: CraftingRecipeStatus) -> CraftingRecipeReadout {
        let recipe = status.recipe
        let itemName = recipe.created.map(coordinator.name(of:)) ?? recipe.editorID ?? recipe.id
            .description
        guard let temper = status.temper else {
            return CraftingRecipeReadout(
                id: recipe.id,
                name: itemName,
                isEligible: status.isReady,
                isOffered: status.eligibility.isOffered,
                category: category(of: recipe)
            )
        }
        let copies = temper.copies.map { qualityName($0, of: temper.item) }
            .joined(separator: ", ")
        return CraftingRecipeReadout(
            id: recipe.id,
            name: "\(itemName) (\(copies))",
            isEligible: status.isReady,
            isOffered: true
        )
    }

    private func category(of recipe: CraftingRecipe) -> CraftingCategoryText? {
        guard
            let created = recipe.created,
            let catalog = coordinator.craftingCatalog,
            let keywords = coordinator.runtime?.inventory.baselines.items.definition(created)?.keywords
        else { return nil }
        return catalog.categories.tab(forKeywords: keywords)
    }

    /// The quality name of `level`, from the weapon or the armour list.
    func qualityName(_ level: Int32, of item: FormID) -> String {
        let isWeapon = coordinator.runtime?.inventory.baselines.items.weapon(item) != nil
        return coordinator.texts.tempering.name(level: level, isWeapon: isWeapon)
    }
}
