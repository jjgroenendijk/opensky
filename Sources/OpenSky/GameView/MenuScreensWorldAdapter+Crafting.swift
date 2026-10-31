// The crafting menu's rows and actions, read from the inventory's open crafting session.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMenus

extension MenuScreensWorldAdapter: CraftingMenuWorld {
    var craftingStationName: String? {
        game.inventory.craftingSnapshot.stationName
    }

    var craftingRecipes: [CraftingMenuRecipe] {
        game.inventory.craftingSnapshot.recipes.filter(\.isOffered).map {
            CraftingMenuRecipe(id: $0.id, name: $0.name, canMake: $0.isEligible)
        }
    }

    func craft(_ recipe: ResolvedFormID) -> String {
        game.inventory.craft(recipe).text(game.mapWorld.settingTexts())
    }

    func closeCraftingStation() {
        game.inventory.closeCraftingSession()
    }

    var alchemyIngredients: [CraftingMenuIngredient]? {
        guard game.inventory.alchemySelection != nil else { return nil }
        return game.inventory.alchemyIngredients.map {
            CraftingMenuIngredient(
                id: $0.id,
                name: "\($0.name) (\($0.count)): \($0.effectsText)",
                isChosen: $0.isChosen
            )
        }
    }

    func toggleIngredient(_ ingredient: FormID) -> String {
        game.inventory.toggleAlchemyIngredient(ingredient).text
    }

    func brewChosenIngredients() -> String {
        game.inventory.brewChosenIngredients().text
    }
}
