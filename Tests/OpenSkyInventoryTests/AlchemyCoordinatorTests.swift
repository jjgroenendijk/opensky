// Alchemy through the inventory shell: a lab opens with no recipes, chosen
// ingredients brew one registered potion, eating and brewing teach effects, the
// perks change counts, and a poison goes on the drawn weapon.

import Foundation
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkyMagicInterface
import OpenSkyProgressionInterface
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct AlchemyCoordinatorTests {
    private typealias Fixture = AlchemyFixture

    private struct Harness {
        let coordinator: InventoryCoordinator
        let world: FakeAlchemyWorld
        let references: FakeWorldReferences
        let conditions: CraftingSessionTests.FakeConditions
        let skills: CraftingSessionTests.FakeSkills

        let inventory: InventoryRuntime
        let store: WorldStateStore
    }

    private static func harness() throws -> Harness {
        let store = WorldStateStore()
        let inventory = try InventoryRuntime(store: store, baselines: Fixture.resolver())
        let references = FakeWorldReferences(entries: [], cell: WorldItemRuntimeTests.cell)
        let world = FakeAlchemyWorld()
        let conditions = CraftingSessionTests.FakeConditions()
        let skills = CraftingSessionTests.FakeSkills()
        var data = InventorySessionData(
            items: WorldItemRuntime(inventory: inventory, references: references)
        )
        data.equipment = try EquipmentCatalog.build(from: Fixture.file())
        data.alchemy.effects = try Fixture.effects()
        data.alchemy.pluginName = Fixture.pluginName
        let coordinator = InventoryCoordinator(
            world: world,
            lockWorld: FakeLockWorld(),
            data: data,
            seams: InventorySeams(recipeConditions: conditions, skillUses: skills)
        )
        coordinator.alchemySelection = []
        return Harness(
            coordinator: coordinator, world: world, references: references,
            conditions: conditions, skills: skills, inventory: inventory, store: store
        )
    }

    private static func carry(_ items: [FormID], _ harness: Harness, count: Int32 = 1) throws {
        for item in items {
            try harness.inventory.add(item, count: count, to: .player)
        }
    }

    @Test func aBrewUsesOneOfEachAndRegistersThePotion() throws {
        let harness = try Self.harness()
        try Self.carry([Fixture.wheat, Fixture.flower], harness, count: 2)
        let lab = harness.coordinator
        lab.toggleAlchemyIngredient(Fixture.wheat)
        let picked = lab.toggleAlchemyIngredient(Fixture.flower)
        #expect(picked.text.contains("Potion of Restore Health"))
        let outcome = lab.brewChosenIngredients()
        #expect(outcome == .brewed(count: 1, item: "Potion of Restore Health", value: 5))
        let potion = try #require(lab.createdPotions.potions.first)
        #expect(harness.inventory.count(of: potion.id, in: .player) == 1)
        #expect(harness.inventory.count(of: Fixture.wheat, in: .player) == 1)
        #expect(harness.inventory.baselines.items.ingestibles[potion.id.rawValue] != nil)
        #expect(lab.ingredientKnowledge.knows(0, of: Fixture.flower))
        #expect(harness.skills.uses.map(\.amount) == [5])
        let alchemy = InventoryCoordinator.alchemySkill
        #expect(harness.skills.uses.first?.action == .craft(skill: alchemy))
        // Both are still carried, so they stay chosen for the next brew.
        #expect(lab.alchemySelection == [Fixture.wheat, Fixture.flower])
    }

    @Test func aFailedBrewStillUsesTheIngredientsAndGivesTheFailedSkillUse() throws {
        let harness = try Self.harness()
        try Self.carry([Fixture.wheat, Fixture.salt], harness)
        let lab = harness.coordinator
        lab.toggleAlchemyIngredient(Fixture.wheat)
        #expect(lab.toggleAlchemyIngredient(Fixture.salt).text.contains("No shared effect"))
        #expect(lab.brewChosenIngredients() == .failed("You failed to create a potion."))
        #expect(harness.inventory.count(of: Fixture.wheat, in: .player) == 0)
        #expect(harness.inventory.count(of: Fixture.salt, in: .player) == 0)
        #expect(harness.skills.uses.map(\.amount) == [5])
        #expect(lab.createdPotions.potions.isEmpty)
    }

    @Test func aLabAllowsThreeIngredientsAndOnlyCarriedOnes() throws {
        let harness = try Self.harness()
        let lab = harness.coordinator
        #expect(lab.toggleAlchemyIngredient(Fixture.wheat) == .noneCarried("Wheat"))
        try Self.carry([Fixture.wheat, Fixture.flower, Fixture.cap, Fixture.poison], harness)
        #expect(
            lab.toggleAlchemyIngredient(Fixture.poison) == .notAnIngredient("Damage Health Poison")
        )
        for item in [Fixture.wheat, Fixture.flower, Fixture.cap] {
            lab.toggleAlchemyIngredient(item)
        }
        #expect(lab.alchemySelection?.count == 3)
        lab.toggleAlchemyIngredient(Fixture.flower)
        #expect(lab.alchemySelection == [Fixture.wheat, Fixture.cap])
        #expect(lab.brewChosenIngredients().text.contains("Poison of Damage Health"))
    }

    @Test func modPotionsCreatedMakesMore() throws {
        let harness = try Self.harness()
        try Self.carry([Fixture.wheat, Fixture.flower], harness)
        harness.world.perkFactors[.modPotionsCreated] = 2
        harness.coordinator.toggleAlchemyIngredient(Fixture.wheat)
        harness.coordinator.toggleAlchemyIngredient(Fixture.flower)
        #expect(harness.coordinator.brewChosenIngredients().text.hasPrefix("Made 2"))
        // Nothing is left, so nothing stays chosen.
        #expect(harness.coordinator.alchemySelection?.isEmpty == true)
    }

    @Test func purityAndEffectivenessReachTheBrew() throws {
        let harness = try Self.harness()
        try Self.carry([Fixture.wheat, Fixture.flower], harness)
        harness.world.perkFactors[.modAlchemyEffectiveness] = 2
        harness.world.purifies = true
        harness.coordinator.toggleAlchemyIngredient(Fixture.wheat)
        harness.coordinator.toggleAlchemyIngredient(Fixture.flower)
        #expect(harness.coordinator.alchemyPreview?.effects == ["Restore Health 17 for 0 s"])
        #expect(harness.world.alchemySeams.last?.isPoison == false)
        #expect(harness.world.alchemySeams.last?.effect?.effect.editorID == "AlchRestoreHealth")
    }

    @Test func eatingTeachesTheFirstEffectOrMoreWithExperimenter() throws {
        let harness = try Self.harness()
        let lab = harness.coordinator
        #expect(lab.learnEatenIngredient(Fixture.wheat) == .learned(
            ingredient: "Wheat", effects: ["Restore Health"]
        ))
        #expect(lab.learnEatenIngredient(Fixture.wheat).text.contains("no new effect"))
        harness.world.perkFactors[.modInitialIngredientEffectsLearned] = 2
        lab.learnEatenIngredient(Fixture.cap)
        #expect(lab.ingredientKnowledge.knownIndices(of: Fixture.cap) == [0, 1])
    }

    @Test func scriptsLearnEffectsOneByOneOrAll() throws {
        let lab = try Self.harness().coordinator
        #expect(lab.learnNextIngredientEffect(Fixture.wheat) == 0)
        #expect(lab.learnNextIngredientEffect(Fixture.wheat) == 1)
        #expect(lab.learnNextIngredientEffect(Fixture.wheat) == -1)
        #expect(lab.learnIngredientEffects(Fixture.flower, indices: nil))
        #expect(lab.ingredientKnowledge.knownIndices(of: Fixture.flower) == [0, 1])
        #expect(!lab.learnIngredientEffects(Fixture.poison, indices: [0]))
        #expect(lab.isHostileItem(Fixture.poison) == true)
        #expect(lab.isHostileItem(Fixture.wheat) == true)
        #expect(lab.isHostileItem(Fixture.flower) == false)
    }

    @Test func aPoisonGoesOnTheDrawnWeaponForTheDoseCount() throws {
        let harness = try Self.harness()
        let lab = harness.coordinator
        try Self.carry([Fixture.poison], harness, count: 2)
        #expect(lab.applyPoison(Fixture.poison) == .noWeapon)
        try Self.carry([InventoryBaselineFixture.sword], harness)
        _ = try lab.equipment?.equip(InventoryBaselineFixture.sword, on: .player)
        harness.world.perkFactors[.modPoisonDoseCount] = 2
        let applied = lab.applyPoison(Fixture.poison)
        #expect(applied.text.contains("Damage Health Poison"))
        guard case let .poisoned(_, _, doses) = applied else {
            Issue.record("expected a poisoned weapon, got \(applied)")
            return
        }
        #expect(doses == 2)
        #expect(lab.playerWeaponPoisons.poisons[InventoryBaselineFixture.sword]?.doses == 2)
        #expect(harness.inventory.count(of: Fixture.poison, in: .player) == 1)
        #expect(lab.applyPoison(Fixture.wheat) == .notAPoison("Wheat"))
    }

    @Test func aLoadPutsTheSavedPotionsBackInTheItemIndex() throws {
        let harness = try Self.harness()
        let items = harness.inventory.baselines.items
        let (state, potion) = CreatedPotionState().adding(
            name: "Potion of Restore Health", isPoison: false, value: 5,
            effects: [
                CreatedPotionEffect(
                    effect: Fixture.restoreHealth,
                    magnitude: 9,
                    area: 0,
                    duration: 0
                )
            ]
        )
        harness.store.set(state, for: .player)
        harness.coordinator.registerCreatedPotions()
        #expect(items.definition(potion.id)?.family == .ingestible)
        harness.store.reset(CreatedPotionState.componentKind, for: .player)
        harness.coordinator.registerCreatedPotions()
        #expect(items.definition(potion.id) == nil)
    }
}

@MainActor
final class FakeAlchemyWorld: InventoryWorld {
    var crosshairInteraction: PlacedInteraction?
    var gameDaysPassed: Float?
    var perkFactors: [PerkEntryPoint: Float] = [:]
    var purifies = false
    private(set) var alchemySeams: [AlchemyConditionResolution] = []

    func dropPlacement() -> DropPlacement? {
        nil
    }

    func nearestActorEntry() -> RuntimeReferenceEntry? {
        nil
    }

    func appearanceSkipReasons(forActor _: FormID) -> [String] {
        []
    }

    func theftBounty(of _: FormID, from _: ReferenceKey) -> Int32 {
        0
    }

    func enchantmentLine(of _: FormID, on _: ReferenceKey) -> String? {
        nil
    }

    var enchantmentCacheReadout: EnchantmentCacheReadout {
        .empty
    }

    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on _: ReferenceKey,
        subjects _: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> Float {
        if entryPoint == .purifyAlchemyIngredients {
            return purifies ? 1 : value
        }
        if entryPoint == .modAlchemyEffectiveness {
            alchemySeams.append(seams.alchemy)
        }
        return value * (perkFactors[entryPoint] ?? 1)
    }
}
