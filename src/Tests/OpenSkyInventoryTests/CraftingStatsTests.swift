// The crafting stats on the journal's Stats page (docs/engine/statistics.md, Crafting).

import OpenSkyFeaturesTesting
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyQuestsInterface
import OpenSkyWorldState
import Testing

@MainActor
struct CraftingStatsTests {
    @Test func eachCraftRaisesTheStatOfWhatItMade() {
        #expect(CraftingStats.stat(of: .weapon, improved: false) == "Weapons Made")
        #expect(CraftingStats.stat(of: .armor, improved: false) == "Armor Made")
        #expect(CraftingStats.stat(of: .weapon, improved: true) == "Weapons Improved")
        #expect(CraftingStats.stat(of: .armor, improved: true) == "Armor Improved")
        #expect(CraftingStats.stat(of: .ingestible, improved: false) == "Potions Mixed")
        #expect(CraftingStats.stat(of: .miscellaneous, improved: false) == nil)
        #expect(CraftingStats.stat(of: .ammunition, improved: false) == nil)
        #expect(CraftingStats.stat(of: nil, improved: false) == nil)
        #expect(CraftingStats.brewStat(isPoison: false) == "Potions Mixed")
        #expect(CraftingStats.brewStat(isPoison: true) == "Poisons Mixed")
    }

    @Test func aForgedSwordCountsAsAWeaponMade() throws {
        let harness = try CraftingSessionTests.harness()
        try harness.inventory.add(InventoryBaselineFixture.lockpick, count: 5, to: .player)
        let store = WorldStateStore()
        let sword = try harness.session.craft(CraftingSessionTests.swordRecipe)
        CraftingStats.count(sword, items: harness.inventory.baselines.items, in: store)
        let picks = try harness.session.craft(CraftingSessionTests.picksRecipe)
        CraftingStats.count(picks, items: harness.inventory.baselines.items, in: store)
        #expect(store.miscStats.values == ["Weapons Made": 1])
    }

    @Test func aHarvestCountsItsIngredients() throws {
        let items = try AlchemyFixture.resolver().items
        let stats = CraftingStats.harvestStats(
            of: [
                InventoryStack(item: AlchemyFixture.wheat, count: 2),
                InventoryStack(item: InventoryBaselineFixture.lockpick, count: 1)
            ],
            items: items
        )
        #expect(stats.map(\.name) == ["Ingredients Harvested"])
        #expect(stats.map(\.count) == [2])
    }
}
