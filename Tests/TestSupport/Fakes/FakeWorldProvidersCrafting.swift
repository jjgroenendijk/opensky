// The crafting and harvest half of the world-provider fake: one station with
// two recipes, one ready and one short of parts, and one plant.

@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory

struct FakeCraftingState {
    var isOpen = false
    var crafted = 0
    var harvested = false
    var lastCraft = "No crafting action yet."
    var lastAction = "No item action yet."
}

extension FakeWorldProviders {
    static let forgeEditorID = "CraftingSmithingForge"
    static let swordRecipe = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x10)
    static let daggerRecipe = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x11)

    var craftingSnapshot: CraftingControlSnapshot {
        CraftingControlSnapshot(
            isAvailable: true,
            stationName: crafting.isOpen ? Self.forgeEditorID : nil,
            skillName: crafting.isOpen ? "Smithing" : nil,
            recipes: crafting.isOpen ? [
                CraftingRecipeReadout(
                    id: Self.swordRecipe, name: "Iron Sword",
                    verdict: "missing Iron Ingot 0 of 1", isEligible: false
                ),
                CraftingRecipeReadout(
                    id: Self.daggerRecipe, name: "Iron Dagger", verdict: "ready", isEligible: true
                )
            ] : [],
            stations: [Self.forgeEditorID],
            harvestTarget: HarvestTargetReadout(
                name: "Mountain Flower", produce: "Blue Mountain Flower",
                isHarvested: crafting.harvested
            ),
            lastCraftText: crafting.lastCraft,
            lastActionText: crafting.lastAction
        )
    }

    func openCraftingStation(_ editorID: String) -> String {
        crafting.isOpen = editorID == Self.forgeEditorID
        crafting.lastCraft = crafting.isOpen
            ? "Opened \(editorID): 2 recipes." : "No station named \(editorID)."
        return crafting.lastCraft
    }

    func craftRecipe(_ id: ResolvedFormID) -> String {
        guard id == Self.daggerRecipe else {
            crafting.lastCraft = "Craft failed: not eligible"
            return crafting.lastCraft
        }
        crafting.crafted += 1
        crafting.lastCraft = "Crafted 1 × Iron Dagger."
        return crafting.lastCraft
    }

    func closeCraftingStation() -> String {
        crafting.isOpen = false
        crafting.lastCraft = "Closed the crafting station."
        return crafting.lastCraft
    }

    func forceHarvest() -> String {
        crafting.harvested = true
        crafting.lastAction = "Harvested Mountain Flower: 1 × Blue Mountain Flower."
        return crafting.lastAction
    }

    func resetHarvest() -> String {
        crafting.harvested = false
        crafting.lastAction = "Reset the harvest of Mountain Flower."
        return crafting.lastAction
    }
}
