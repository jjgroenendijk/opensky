// The alchemy formulas on synthetic effects: shared effects, power from the skill,
// magnitude, cost, potion or poison, Purity, and the perk multiplier. Expected
// numbers follow UESP "Skyrim:Alchemy" by hand: at skill 15 the power is 4.3.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import Testing

@MainActor
struct AlchemyRulesTests {
    private typealias Fixture = AlchemyFixture

    private struct Lab {
        let store: MagicEffectStore
        let items: ItemDefinitionStore

        func ingredients(_ ids: [FormID]) -> [AlchemyIngredient] {
            ids.compactMap { id in
                items.ingredients[id.rawValue]
                    .map { AlchemyIngredient(id: id, effects: $0.effects) }
            }
        }

        func resolve(_ id: FormID) -> ResolvedMagicEffect? {
            store.resolve(id, fromPlugin: Fixture.pluginName)
        }

        func brew(_ ids: [FormID], skill: Float = 15, perks: AlchemyPerks = .none) -> AlchemyBrew? {
            AlchemyRules.brew(
                ingredients(ids),
                resolve: resolve,
                power: AlchemyRules.powerFactor(skill: skill, settings: .vanilla),
                perks: perks
            )
        }
    }

    private static func lab() throws -> Lab {
        try Lab(store: Fixture.effects(), items: Fixture.resolver().items)
    }

    @Test func theSkillSetsThePower() {
        #expect(AlchemyRules.powerFactor(skill: 0, settings: .vanilla) == 4)
        #expect(AlchemyRules.powerFactor(skill: 100, settings: .vanilla) == 6)
    }

    @Test func onlyAnEffectTwoIngredientsShareCounts() throws {
        let lab = try Self.lab()
        #expect(AlchemyRules.shared(lab.ingredients([Fixture.wheat]), resolve: lab.resolve).isEmpty)
        let shared = AlchemyRules.shared(
            lab.ingredients([Fixture.wheat, Fixture.flower]), resolve: lab.resolve
        )
        #expect(shared.map(\.effect.effect.editorID) == ["AlchRestoreHealth"])
        // The flower's Restore Health 2 costs more than the wheat's 1, so it is used.
        #expect(shared.first?.entry.magnitude == 2)
        #expect(shared.first?.sources == [Fixture.wheat: 0, Fixture.flower: 0])
    }

    /// Magnitude round(2 × 4.3) = 9; value floor(0.5 × 9^1.1) = 5.
    @Test func aPotionTakesItsMagnitudeAndValueFromThePower() throws {
        let brew = try #require(try Self.lab().brew([Fixture.wheat, Fixture.flower]))
        #expect(!brew.isPoison)
        #expect(brew.effects.map(\.result.magnitude) == [9])
        #expect(brew.value == 5)
        #expect(brew.skillValue == 5)
        #expect(brew.learned == [Fixture.wheat: [0], Fixture.flower: [0]])
    }

    @Test func aHostileStrongestEffectMakesAPoison() throws {
        let brew = try #require(try Self.lab().brew([Fixture.wheat, Fixture.cap]))
        #expect(brew.isPoison)
        // Magnitude round(1 × 4.3) = 4; value floor(3 × 4^1.1) = 13.
        #expect(brew.effects.map(\.result.magnitude) == [4])
        #expect(brew.value == 13)
    }

    /// Fortify Smithing 4 for 258 s costs floor((4 × 25.8)^1.1) = 164 and names it.
    @Test func threeIngredientsShareThreeEffectsAndTheCostliestLeads() throws {
        let brew = try #require(try Self.lab().brew([Fixture.wheat, Fixture.flower, Fixture.cap]))
        #expect(!brew.isPoison)
        #expect(brew.effects.map(\.effect.effect.editorID) == [
            "AlchFortifySmithing", "AlchDamageHealth", "AlchRestoreHealth"
        ])
        #expect(brew.effects.first?.result.duration == 258)
        #expect(brew.value == 164 + 13 + 5)
    }

    @Test func purityKeepsOnlyTheEffectsOfTheResultsKind() throws {
        let purity = AlchemyPerks(effectiveness: { _, _ in 1 }, purifies: true)
        let brew = try #require(
            try Self.lab().brew([Fixture.wheat, Fixture.flower, Fixture.cap], perks: purity)
        )
        #expect(!brew.effects.contains { AlchemyRules.isHostile($0.effect) })
        #expect(brew.effects.count == 2)
    }

    /// An Alchemist-style perk doubles the power for a potion: round(2 × 8.6) = 17.
    @Test func modAlchemyEffectivenessScalesEachEffect() throws {
        let doubled = AlchemyPerks(
            effectiveness: { _, isPoison in isPoison ? 1 : 2 },
            purifies: false
        )
        let brew = try #require(try Self.lab().brew(
            [Fixture.wheat, Fixture.flower],
            perks: doubled
        ))
        #expect(brew.effects.map(\.result.magnitude) == [17])
        // The skill use counts the value without perks.
        #expect(brew.skillValue == 5)
    }

    @Test func noSharedEffectBrewsNothing() throws {
        #expect(try Self.lab().brew([Fixture.flower]) == nil)
    }

    @Test func aBrewedPotionStacksWithAnEqualOne() {
        let effects = [CreatedPotionEffect(
            effect: Fixture.restoreHealth,
            magnitude: 9,
            area: 0,
            duration: 0
        )]
        let (first, potion) = CreatedPotionState().adding(
            name: "Potion of Restore Health", isPoison: false, value: 5, effects: effects
        )
        #expect(potion.id.rawValue == CreatedPotionState.firstObjectID)
        let (second, again) = first.adding(
            name: "Potion of Restore Health", isPoison: false, value: 5, effects: effects
        )
        #expect(again == potion)
        #expect(second == first)
        let (third, other) = second.adding(
            name: "Poison",
            isPoison: true,
            value: 5,
            effects: effects
        )
        #expect(other.id.rawValue == CreatedPotionState.firstObjectID + 1)
        #expect(third.potions.count == 2)
        #expect(potion.ingestible.itemValue.weight == CreatedPotion.weight)
        #expect(other.ingestible.flags.contains(.poison))
    }

    @Test func knowledgeAndPoisonStateCountAsExpected() {
        let knowledge = IngredientKnowledgeState().learning([0, 2], of: Fixture.wheat)
        #expect(knowledge.knownIndices(of: Fixture.wheat) == [0, 2])
        #expect(!knowledge.knows(1, of: Fixture.wheat))
        let poisons = WeaponPoisonState()
            .applying(WeaponPoison(poison: Fixture.poison, doses: 2), to: Fixture.wheat)
        let (once, first) = poisons.spendingDose(of: Fixture.wheat)
        let (twice, second) = once.spendingDose(of: Fixture.wheat)
        #expect(first == Fixture.poison && second == Fixture.poison)
        #expect(twice.isEmpty)
        #expect(twice.spendingDose(of: Fixture.wheat).poison == nil)
    }
}
