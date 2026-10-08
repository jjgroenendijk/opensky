// A tempering bench: rows for held items only, one copy improved per temper, the
// count kept, and the skill cap respected.

import FeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import Testing

extension CraftingSessionTests {
    private typealias Items = InventoryBaselineFixture

    @Test func aTemperingBenchListsOnlyHeldItems() throws {
        let harness = try Self.harness(bench: .smithingWeapon)
        #expect(harness.session.statuses.isEmpty)
        try harness.inventory.add(Items.sword, count: 1, to: .player)
        let row = try #require(harness.session.statuses.first)
        #expect(harness.session.statuses.count == 1)
        #expect(row.recipe.id == Self.swordRecipe)
        #expect(row.temper == TemperTarget(item: Items.sword, copies: [0], maximum: 1))
        #expect(harness.conditions.temperingEnchanted.last == false)
    }

    @Test func aTemperImprovesOneCopyAndKeepsTheCount() throws {
        let harness = try Self.harness(bench: .smithingWeapon)
        try harness.inventory.add(Items.sword, count: 2, to: .player)
        try harness.inventory.add(Items.lockpick, count: 4, to: .player)
        let first = try harness.session.craft(Self.swordRecipe)
        #expect(first.improved == TemperStep(from: 0, to: 1))
        #expect(harness.inventory.count(of: Items.sword, in: .player) == 2)
        #expect(harness.inventory.count(of: Items.lockpick, in: .player) == 2)
        #expect(harness.inventory.temperedItems(of: .player).copies(of: Items.sword, held: 2)
            == [1, 0])
        #expect(harness.inventory.temperLevel(of: Items.sword, in: .player) == 1)
        try harness.session.craft(Self.swordRecipe)
        #expect(harness.inventory.temperedItems(of: .player).copies(of: Items.sword, held: 2)
            == [1, 1])
        #expect(harness.skills.uses.count == 2)
    }

    @Test func aCopyAtTheSkillCapCannotBeImproved() throws {
        let harness = try Self.harness(bench: .smithingWeapon)
        try harness.inventory.add(Items.sword, count: 1, to: .player)
        try harness.inventory.add(Items.lockpick, count: 4, to: .player)
        try harness.session.craft(Self.swordRecipe)
        #expect(harness.session.statuses.first?.isReady == false)
        #expect(throws: CraftingError.notImprovable(Self.swordRecipe)) {
            try harness.session.craft(Self.swordRecipe)
        }
        #expect(harness.inventory.count(of: Items.lockpick, in: .player) == 2)
        harness.conditions.smithing = 100
        let outcome = try harness.session.craft(Self.swordRecipe)
        #expect(outcome.improved == TemperStep(from: 1, to: 4))
    }
}

struct TemperingTests {
    @Test func theSkillSetsTheBestQuality() {
        #expect(Tempering.maximumLevel(smithing: 15) == 1)
        #expect(Tempering.maximumLevel(smithing: 100) == 4)
        #expect(Tempering.maximumLevel(smithing: 100, perk: 1) == 6)
        #expect(Tempering.maximumLevel(smithing: .nan) == 0)
    }

    @Test func bodyArmorGetsTheFullBonus() {
        #expect(Tempering.bonus(level: 0, isBodyArmor: true) == 0)
        #expect(Tempering.bonus(level: 1, isBodyArmor: false) == 1)
        #expect(abs(Tempering.bonus(level: 6, isBodyArmor: true) - 20) < 0.001)
        #expect(Tempering.name(level: 6) == "Legendary")
        #expect(Tempering.name(level: 0) == "plain")
    }

    @Test func heldCopiesClampTheTemperedList() throws {
        let item = FormID(0x200)
        let state = TemperedItemState(levels: [item.rawValue: [0, 2, 5]])
        #expect(state.copies(of: item, held: 1) == [5])
        #expect(state.copies(of: item, held: 3) == [5, 2, 0])
        let improved = try #require(state.improving(item, held: 3, from: 0, to: 3))
        #expect(improved.copies(of: item, held: 3) == [5, 3, 2])
        #expect(state.improving(item, held: 3, from: 4, to: 5) == nil)
    }
}
