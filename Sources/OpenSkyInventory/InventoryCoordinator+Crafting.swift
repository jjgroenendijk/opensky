// Harvest and crafting actions of the inventory domain. The rules live in
// `WorldItemRuntime+Harvest` and `CraftingSession`. See docs/engine/crafting.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldInterface

extension InventoryCoordinator {
    public func wireCrafting(
        catalog: CraftingCatalog?,
        conditions: any RecipeConditionChecking,
        skills: any SkillUseReporting
    ) {
        craftingCatalog = catalog
        recipeConditions = conditions
        skillUses = skills
    }

    // MARK: - Harvest

    /// `interaction` with its runtime label: a harvested plant, or a locked target.
    public func labelled(_ interaction: PlacedInteraction) -> PlacedInteraction {
        locks.labelled(runtime?.labelled(interaction) ?? interaction)
    }

    @discardableResult
    public func harvest(_ interaction: PlacedInteraction) -> String {
        guard let runtime else { return InventoryCore.noRuntimeText }
        do {
            let outcome = try runtime.harvest(interaction)
            world?.refreshInteractionTarget()
            let items = outcome.granted.map { "\($0.count) × \(name(of: $0.item))" }
            return note("Harvested \(interaction.name): \(items.joined(separator: ", ")).")
        } catch {
            return note("Harvest failed: \(String(describing: error))")
        }
    }

    @discardableResult
    public func harvestInteractionTarget() -> String {
        guard let interaction = world?.crosshairInteraction else {
            return note("Nothing under the crosshair to harvest.")
        }
        return harvest(interaction)
    }

    @discardableResult
    public func resetHarvestOfInteractionTarget() -> String {
        guard let runtime else { return InventoryCore.noRuntimeText }
        guard let interaction = world?.crosshairInteraction else {
            return note("Nothing under the crosshair to reset.")
        }
        do {
            try runtime.resetHarvest(interaction)
            world?.refreshInteractionTarget()
            return note("Reset the harvest of \(interaction.name).")
        } catch {
            return note("Reset failed: \(String(describing: error))")
        }
    }

    // MARK: - Crafting

    /// Opens a session for a station activation, replacing any open one.
    @discardableResult
    public func openCraftingSession(_ event: CraftingActivationEvent) -> String {
        guard let runtime else { return noteCraft(InventoryCore.noRuntimeText) }
        guard let craftingCatalog else { return noteCraft("No recipe data is loaded.") }
        crafting = CraftingSession(
            event: event,
            catalog: craftingCatalog,
            inventory: runtime.inventory,
            player: runtime.player,
            conditions: recipeConditions,
            skills: skillUses
        )
        let count = crafting?.recipes.count ?? 0
        return noteCraft("Opened \(event.interaction.name): \(count) recipes.")
    }

    /// The dev control: a session at a station base, without walking to one.
    @discardableResult
    public func openCraftingSession(station editorID: String) -> String {
        guard let choice = craftingCatalog?.stations.first(where: { $0.editorID == editorID })
        else { return noteCraft("No station named \(editorID).") }
        let interaction = PlacedInteraction(
            reference: choice.base,
            base: choice.base,
            position: .zero,
            name: choice.editorID,
            action: .use,
            actionLabel: InteractionAction.use.defaultLabel,
            sounds: nil,
            station: CraftingStation(workbench: choice.workbench, keywords: choice.keywords)
        )
        guard let event = CraftingActivationEvent(interaction: interaction) else {
            return noteCraft("\(editorID) is no crafting station.")
        }
        return openCraftingSession(event)
    }

    @discardableResult
    public func craft(_ recipe: ResolvedFormID) -> String {
        guard let crafting else { return noteCraft("No crafting station is open.") }
        do {
            let outcome = try crafting.craft(recipe)
            return noteCraft(
                "Crafted \(outcome.created.count) × \(name(of: outcome.created.item))."
            )
        } catch {
            return noteCraft("Craft failed: \(String(describing: error))")
        }
    }

    @discardableResult
    public func closeCraftingSession() -> String {
        guard crafting != nil else { return noteCraft("No crafting station is open.") }
        crafting = nil
        return noteCraft("Closed the crafting station.")
    }

    private func noteCraft(_ text: String) -> String {
        lastCraftText = text
        return text
    }
}
