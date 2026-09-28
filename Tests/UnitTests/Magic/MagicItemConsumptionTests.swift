// Consuming a potion and eating an ingredient (issue #469, roadmap item 19.6):
// the inventory half of the first consumer.
//
// Records are synthetic and built in code (`ActiveEffectFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary"). The ingredient rule
// is UESP "Skyrim:Alchemy Effects", cited at `ItemDefinitionStore.magicItemUse`.

import Foundation
@testable import opensky
import Testing

@MainActor
struct MagicItemConsumptionTests {
    private let potion = FormID(0x0000_0700)
    private let ingredient = FormID(0x0000_0701)
    private let sword = FormID(0x0000_0702)

    private struct Harness {
        let effects: ActiveEffectRuntime
        let inventory: InventoryRuntime
        let store: WorldStateStore
    }

    private func harness() throws -> Harness {
        let file = try ActiveEffectFixture.plugin(
            records: ActiveEffectFixture.effectRecords + [
                ActiveEffectFixture.ingestible(
                    formID: potion.rawValue,
                    editorID: "TestHealingPotion",
                    effects: [
                        ActiveEffectFixture.EffectSpec(
                            ActiveEffectFixture.restoreHealth, magnitude: 25
                        )
                    ]
                ),
                ActiveEffectFixture.ingredient(
                    formID: ingredient.rawValue,
                    editorID: "TestIngredient",
                    effects: [
                        ActiveEffectFixture.EffectSpec(
                            ActiveEffectFixture.restoreHealth, magnitude: 5
                        ),
                        ActiveEffectFixture.EffectSpec(
                            ActiveEffectFixture.damageHealth, magnitude: 40
                        )
                    ]
                ),
                ESMFixture.record(
                    "WEAP",
                    formID: sword.rawValue,
                    data: ESMFixture.field("EDID", ESMFixture.zstring("TestSword"))
                        + ESMFixture.field(
                            "DATA",
                            InventoryFixture.weaponData(value: 10, weight: 9, damage: 8)
                        )
                )
            ]
        )
        let store = WorldStateStore()
        let baselines = InventoryBaselineResolver.build(from: file)
        let values = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 100),
                    regenPercentPerSecond: .zero
                )
            )
        )
        return Harness(
            effects: ActiveEffectRuntime(
                values: values,
                effects: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)])
            ),
            inventory: InventoryRuntime(store: store, baselines: baselines),
            store: store
        )
    }

    /// The milestone's headline path: the player carries a healing potion,
    /// drinks it, loses the unit and gains the health.
    @Test func drinkingAHealingPotionRemovesOneUnitAndRestoresHealth() throws {
        let harness = try harness()
        var effects = harness.effects
        try harness.inventory.add(potion, count: 2, to: .player)
        effects.values.damage(.health, by: 40, on: .player)

        let outcome = try effects.consume(
            potion,
            from: .player,
            on: .player,
            inventory: harness.inventory,
            fromPlugin: ActiveEffectFixture.pluginName
        )
        #expect(outcome.kind == .potion)
        #expect(outcome.entryCount == 1)
        #expect(outcome.stored.isEmpty)
        #expect(harness.inventory.count(of: potion, in: .player) == 1)
        #expect(effects.values.current(of: .player).health == 85)
    }

    /// "Eating a sample of that ingredient will provide a small version of that
    /// effect" — the first effect only, so the second one never lands.
    @Test func eatingAnIngredientAppliesOnlyItsFirstEffect() throws {
        let harness = try harness()
        var effects = harness.effects
        try harness.inventory.add(ingredient, count: 1, to: .player)
        effects.values.damage(.health, by: 20, on: .player)

        let outcome = try effects.consume(
            ingredient,
            from: .player,
            on: .player,
            inventory: harness.inventory,
            fromPlugin: ActiveEffectFixture.pluginName
        )
        #expect(outcome.kind == .ingredient)
        #expect(outcome.entryCount == 1)
        // The 40-point damage-health effect is the ingredient's second and is
        // not applied by eating it.
        #expect(effects.values.current(of: .player).health == 85)
        #expect(harness.inventory.count(of: ingredient, in: .player) == 0)
    }

    /// Something that is not an ALCH or an INGR is refused and costs nothing.
    @Test func consumingSomethingInedibleIsRefused() throws {
        let harness = try harness()
        var effects = harness.effects
        try harness.inventory.add(sword, count: 1, to: .player)
        #expect(throws: MagicItemConsumeError.notConsumable(sword)) {
            try effects.consume(
                sword,
                from: .player,
                on: .player,
                inventory: harness.inventory,
                fromPlugin: ActiveEffectFixture.pluginName
            )
        }
        #expect(harness.inventory.count(of: sword, in: .player) == 1)
    }

    /// A potion the player does not carry applies nothing.
    @Test func consumingWhatIsNotCarriedIsRefused() throws {
        let harness = try harness()
        var effects = harness.effects
        #expect(throws: MagicItemConsumeError.noneCarried(potion)) {
            try effects.consume(
                potion,
                from: .player,
                on: .player,
                inventory: harness.inventory,
                fromPlugin: ActiveEffectFixture.pluginName
            )
        }
        #expect(effects.values.current(of: .player).health == 100)
    }
}
