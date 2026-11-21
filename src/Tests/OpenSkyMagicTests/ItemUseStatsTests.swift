// The use and reading stats on the journal's Stats page (docs/engine/statistics.md).

import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyQuestsInterface
import Testing

@MainActor
struct ItemUseStatsTests {
    private static let potion = FormID(0x0700)
    private static let ingredient = FormID(0x0701)

    @Test func eachUseRaisesTheStatOfWhatWasUsed() {
        #expect(ItemUseStats.stat(of: .potion, isFood: false, isPoison: false) == "Potions Used")
        #expect(ItemUseStats.stat(of: .potion, isFood: true, isPoison: false) == "Food Eaten")
        #expect(ItemUseStats.stat(of: .potion, isFood: false, isPoison: true) == nil)
        #expect(ItemUseStats.stat(of: .ingredient, isFood: false, isPoison: false)
            == "Ingredients Eaten")
        #expect(ItemUseStats.stat(of: .spell, isFood: false, isPoison: false) == nil)
    }

    @Test func aSkillBookIsNotABookRead() {
        #expect(ItemUseStats.bookStats(isSkillBook: true, taughtSpell: false)
            == ["Skill Books Read"])
        #expect(ItemUseStats.bookStats(isSkillBook: false, taughtSpell: true)
            == ["Books Read", "Spells Learned"])
    }

    @Test func drinkingAndEatingCountOnce() throws {
        let file = try ActiveEffectFixture.plugin(records: ActiveEffectFixture.effectRecords + [
            ActiveEffectFixture.ingestible(
                formID: Self.potion.rawValue, editorID: "TestPotion",
                effects: [.init(ActiveEffectFixture.restoreHealth, magnitude: 5)]
            ),
            ActiveEffectFixture.ingredient(
                formID: Self.ingredient.rawValue, editorID: "TestIngredient",
                effects: [.init(ActiveEffectFixture.restoreHealth, magnitude: 1)]
            )
        ])
        let plugin = ActiveEffectFixture.pluginName
        let inventory = FakeInventory(baselines: InventoryBaselineResolver.build(from: file))
        try inventory.add(Self.potion, count: 1, to: .player)
        try inventory.add(Self.ingredient, count: 1, to: .player)
        let world = FakeMagicWorld()
        world.inventory = inventory
        var data = MagicSessionData()
        data.effects = MagicEffectsData(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(plugin, file)]),
            pluginName: plugin,
            conditionRegistry: ConditionFunctionRegistry()
        )
        let coordinator = MagicCoordinator(world: world, data: data)
        _ = coordinator.itemUse.consumeMagicItem(Self.potion)
        _ = coordinator.itemUse.consumeMagicItem(Self.ingredient)
        let stats = try #require(coordinator.effects?.store.miscStats)
        #expect(stats.values == ["Potions Used": 1, "Ingredients Eaten": 1])
    }

    @Test func aTomeCountsItsFirstReadingAndItsSpell() throws {
        let coordinator = try MagicCoordinatorTests.castingWired(FakeMagicWorld())
        for _ in 0 ..< 2 {
            coordinator.controlPanels.readSpellTome(
                FormID(SpellbookFixture.Book.healingTome),
                spell: FormID(SpellbookFixture.Spell.healing)
            )
        }
        coordinator.spellTomes.readSkillBook(FormID(0x0700), skill: 12)
        let stats = try #require(coordinator.caster?.spellbook.store.miscStats)
        #expect(stats.values == ["Books Read": 1, "Spells Learned": 1, "Skill Books Read": 1])
    }
}
