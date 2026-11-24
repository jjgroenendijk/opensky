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
        let session = coordinator.crafting
        var snapshot = CraftingControlSnapshot(
            stationName: session?.interaction.name,
            header: session.map {
                CraftingMenuText.header(
                    station: $0.station, name: $0.interaction.name,
                    texts: coordinator.texts.crafting
                )
            },
            recipes: session?.statuses.map(recipeReadout) ?? []
        )
        snapshot.station = session?.station
        snapshot.description = session.map {
            CraftingMenuText.description(station: $0.station, texts: coordinator.texts.crafting)
        }
        return snapshot
    }

    private func recipeReadout(_ status: CraftingRecipeStatus) -> CraftingRecipeReadout {
        let recipe = status.recipe
        let itemName = recipe.created.map(coordinator.name(of:)) ?? recipe.editorID ?? recipe.id
            .description
        guard let temper = status.temper else {
            var readout = CraftingRecipeReadout(
                id: recipe.id,
                name: itemName,
                isEligible: status.isReady,
                isOffered: status.eligibility.isOffered,
                category: category(of: recipe)
            )
            readout.created = recipe.created
            readout.requirements = requirements(of: recipe)
            return readout
        }
        let copies = temper.copies.map { qualityName($0, of: temper.item) }
            .joined(separator: ", ")
        var readout = CraftingRecipeReadout(
            id: recipe.id,
            name: "\(itemName) (\(copies))",
            isEligible: status.isReady,
            isOffered: true
        )
        readout.created = recipe.created
        readout.requirements = requirements(of: recipe)
        return readout
    }

    /// "Iron Ingot (3/1), Leather Strips (0/2)": carried, then needed.
    private func requirements(of recipe: CraftingRecipe) -> String? {
        guard let session = coordinator.crafting else { return nil }
        let parts = recipe.components.compactMap { component -> String? in
            guard let item = component.item ?? component.choices.first else { return nil }
            let held = component.choices.isEmpty
                ? session.inventory.count(of: item, in: session.player)
                : component.choices.reduce(0) {
                    $0 + session.inventory.count(of: $1, in: session.player)
                }
            return "\(coordinator.name(of: item)) (\(held)/\(component.count))"
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func category(of recipe: CraftingRecipe) -> CraftingCategoryText? {
        guard
            let created = recipe.created,
            let catalog = coordinator.craftingCatalog,
            let items = coordinator.runtime?.inventory.baselines.items,
            let keywords = items.definition(created)?.keywords
        else { return nil }
        let isFood = items.ingestibles[created.rawValue]?.flags.contains(.food) == true
        return catalog.categories.tab(forKeywords: keywords, isFood: isFood)
    }

    /// The quality name of `level`, from the weapon or the armour list.
    func qualityName(_ level: Int32, of item: FormID) -> String {
        let isWeapon = coordinator.runtime?.inventory.baselines.items.weapon(item) != nil
        return coordinator.texts.tempering.name(level: level, isWeapon: isWeapon)
    }
}
