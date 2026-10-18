// The crafting menu's rows and actions, read from the inventory's open crafting session.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventory
import OpenSkyMenus

extension MenuScreensWorldAdapter: CraftingMenuWorld {
    var craftingStationName: String? {
        game.inventory.craftingSnapshot.stationName
    }

    var craftingRecipes: [CraftingMenuRecipe] {
        game.inventory.craftingSnapshot.recipes.map {
            CraftingMenuRecipe(id: $0.id, name: $0.name, canMake: $0.isEligible)
        }
    }

    func craft(_ recipe: ResolvedFormID) -> String {
        game.inventory.craft(recipe).text
    }

    func closeCraftingStation() {
        game.inventory.closeCraftingSession()
    }
}
