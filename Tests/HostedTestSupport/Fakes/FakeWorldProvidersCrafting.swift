// The crafting, harvest, and alchemy part of the world-provider fake: one station
// with two recipes, one ready and one short of parts, one plant, and one lab.

@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory

struct FakeCraftingState {
    var isOpen = false
    var crafted = 0
    var harvested = false
    var lastCraft = "No crafting action yet."
    var lastAction = "No item action yet."
    var labOpen = false
    var chosen: [FormID] = []
    var brewed = 0
    var lastAlchemy = "No alchemy action yet."
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
                resetDays: crafting.harvested ? 10 : nil
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

extension FakeWorldProviders {
    static let labEditorID = "CraftingAlchemyWorkbench"
    static let wheat = FormID(0x0004_B0BA)
    static let mountainFlower = FormID(0x0007_7E1C)

    var alchemySnapshot: AlchemyControlSnapshot {
        AlchemyControlSnapshot(
            isAvailable: true,
            labName: crafting.labOpen ? Self.labEditorID : nil,
            labs: [Self.labEditorID],
            ingredients: [(Self.wheat, "Wheat"), (Self.mountainFlower, "Blue Mountain Flower")]
                .map { item, name in
                    AlchemyIngredientReadout(
                        id: item, name: name, count: 2, effects: ["Restore Health", nil],
                        isChosen: crafting.chosen.contains(item)
                    )
                },
            poisons: [],
            previewText: crafting.chosen.count == 2 ? "Makes Potion of Restore Health" : "",
            weaponPoisonText: "none",
            brewedCount: crafting.brewed,
            knownEffectCount: 2,
            lastActionText: crafting.lastAlchemy
        )
    }

    func openAlchemyLab(_ editorID: String) -> CraftingActionOutcome {
        crafting.labOpen = editorID == Self.labEditorID
        return noteCraft(crafting.labOpen
            ? .openedLab(editorID, ingredients: 2) : .noStationNamed(editorID))
    }

    func toggleAlchemyIngredient(_ id: FormID) -> AlchemyActionOutcome {
        if let index = crafting.chosen.firstIndex(of: id) {
            crafting.chosen.remove(at: index)
            return noteAlchemy(.dropped("\(id)", preview: ""))
        }
        crafting.chosen.append(id)
        return noteAlchemy(.picked("\(id)", preview: ""))
    }

    func clearAlchemyIngredients() -> AlchemyActionOutcome {
        crafting.chosen = []
        return noteAlchemy(.cleared)
    }

    func brewChosenIngredients() -> AlchemyActionOutcome {
        guard crafting.chosen.count >= 2 else { return noteAlchemy(.needsTwo) }
        crafting.brewed += 1
        return noteAlchemy(.brewed(count: 1, item: "Potion of Restore Health", value: 17))
    }

    func eatIngredient(_ id: FormID) {
        noteAlchemy(.learned(ingredient: "\(id)", effects: ["Restore Health"]))
    }

    func applyPoison(_: FormID) -> AlchemyActionOutcome {
        noteAlchemy(.noWeapon)
    }

    @discardableResult
    private func noteAlchemy(_ outcome: AlchemyActionOutcome) -> AlchemyActionOutcome {
        crafting.lastAlchemy = outcome.text
        return outcome
    }
}
