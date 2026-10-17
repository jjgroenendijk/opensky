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
                isHarvested: crafting.harvested,
                daysUntilRegrowth: crafting.harvested ? 10 : nil
            ),
            lastCraftText: crafting.lastCraft,
            lastActionText: crafting.lastAction
        )
    }

    func openCraftingStation(_ editorID: String) -> CraftingActionOutcome {
        crafting.isOpen = editorID == Self.forgeEditorID
        return noteCraft(crafting.isOpen
            ? .opened(station: editorID, recipes: 2) : .noStationNamed(editorID))
    }

    func craftRecipe(_ id: ResolvedFormID) -> CraftingActionOutcome {
        guard id == Self.daggerRecipe else {
            return noteCraft(.craftFailed(reason: "not eligible"))
        }
        crafting.crafted += 1
        return noteCraft(.crafted(count: 1, item: "Iron Dagger"))
    }

    func closeCraftingStation() -> CraftingActionOutcome {
        crafting.isOpen = false
        return noteCraft(.closed)
    }

    func forceHarvest() -> ItemActionOutcome {
        crafting.harvested = true
        return noteItem(.harvested(plant: "Mountain Flower", items: ["1 × Blue Mountain Flower"]))
    }

    func resetHarvest() -> ItemActionOutcome {
        crafting.harvested = false
        return noteItem(.grewBack("Mountain Flower"))
    }

    private func noteCraft(_ outcome: CraftingActionOutcome) -> CraftingActionOutcome {
        crafting.lastCraft = outcome.text
        return outcome
    }

    private func noteItem(_ outcome: ItemActionOutcome) -> ItemActionOutcome {
        crafting.lastAction = outcome.text
        return outcome
    }
}
