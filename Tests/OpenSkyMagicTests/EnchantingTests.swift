// Enchanting: the UESP formulas, disenchanting to learn a base, and enchanting a plain
// weapon or ring with a filled gem. Records are synthetic (`EnchantingFixture`).

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState
import Testing

@MainActor
struct EnchantingTests {
    private typealias Records = EnchantingFixture
    private typealias Gems = SoulGemFixture

    @MainActor
    private struct Session {
        let coordinator: MagicCoordinator
        let world: FakeMagicWorld
        let inventory: FakeInventory

        func key(_ id: FormID) -> ReferenceKey {
            .plugin(name: ActiveEffectFixture.pluginName.lowercased(), objectID: id.rawValue)
        }

        func gem(_ item: FormID) throws -> SoulGemCandidate {
            let snapshot = coordinator.enchantingSnapshot
            return try #require(snapshot.gems.first { $0.gem.item == item }?.gem)
        }

        /// The player knows `bases` already.
        func knowing(_ bases: [FormID]) {
            coordinator.withEffects { runtime in
                runtime.store.set(EnchantingState(known: bases.map(key)), for: .player)
            }
        }
    }

    private func session(skill: Float = 100, carrying items: [FormID]) throws -> Session {
        let file = try Records.plugin()
        let plugin = ActiveEffectFixture.pluginName
        let enchantments = EnchantmentStore(plugins: [(plugin, file)])
        let inventory = FakeInventory(baselines: InventoryBaselineResolver.build(
            from: file,
            enchantments: ItemEnchantmentResolver(store: enchantments, pluginName: plugin)
        ))
        for item in items {
            try inventory.add(item, count: 1, to: .player)
        }
        let world = FakeMagicWorld()
        world.inventory = inventory
        world.equipment = FakeHandEquipment()
        var data = MagicSessionData()
        data.effects = MagicEffectsData(
            values: FixedActorValues(indexedValue: skill),
            store: MagicEffectStore(plugins: [(plugin, file)]),
            pluginName: plugin,
            conditionRegistry: ConditionFunctionRegistry()
        )
        data.enchantments = enchantments
        let coordinator = MagicCoordinator(world: world, data: data)
        return Session(coordinator: coordinator, world: world, inventory: inventory)
    }

    @Test func theSkillAndSoulTermsFollowUESP() {
        #expect(abs(EnchantingRules.skillMultiplier(100) - 1.252_94) < 0.000_01)
        #expect(EnchantingRules.skillMultiplier(0) == 1)
        #expect(EnchantingRules.soulMultiplier(.common) == Float(1) / 3)
        #expect(EnchantingRules.rechargeExperience(.grand) == 0.6)
    }

    /// At skill 0 one use of a cost-100 base costs 3 * 100^1.1, about 475; a petty
    /// soul holds 250, so the power drops until one use costs the whole soul.
    @Test func aSmallSoulLowersAWeaponsPowerToBuyOneUse() {
        let input = EnchantingInput(skill: 0, soul: .petty, bases: [EnchantingBase(cost: 100)])
        let scale = EnchantingRules.weapon(input)
        #expect(scale.capacity == 250)
        #expect(scale.costPerUse == 250)
        #expect(abs(scale.powers[0] - pow(250 / (3 * pow(100, 1.1)), 1 / 1.1)) < 0.000_1)
    }

    @Test func disenchantingTeachesTheRootBaseAndDestroysTheItem() throws {
        let trial = try session(carrying: [Records.fireSword])
        let outcome = trial.coordinator.disenchant(Records.fireSword)
        guard case .learned = outcome else {
            Issue.record("expected a learned base, got \(outcome)")
            return
        }
        #expect(trial.coordinator.enchantingState.known == [trial.key(Records.fireBase)])
        #expect(trial.inventory.count(of: Records.fireSword, in: .player) == 0)
        // 100 + 0.12 * 1000 + 8 * 30 = 460 gold, 360 of it the enchantment's.
        #expect(trial.world.skillUses.map(\.amount) == [0.9])
    }

    @Test func aKnownBaseIsNotLearnedTwice() throws {
        let trial = try session(carrying: [Records.fireSword])
        trial.knowing([Records.fireBase])
        #expect(trial.coordinator.disenchant(Records.fireSword) == .refused(.alreadyKnown))
        #expect(trial.inventory.count(of: Records.fireSword, in: .player) == 1)
    }

    /// Skill 100 and a grand soul: 30 * 1.2529 rounds down to 37, and the gem is spent.
    @Test func aRingTakesAnApparelBaseScaledBySkillAndSoul() throws {
        let trial = try session(carrying: [Records.ring, Gems.grandFilled])
        trial.knowing([Records.healthBase])
        let outcome = try trial.coordinator.enchant(
            Records.ring, with: [trial.key(Records.healthBase)], gem: trial.gem(Gems.grandFilled)
        )
        guard case .enchanted = outcome else {
            Issue.record("expected an enchanted ring, got \(outcome)")
            return
        }
        let profile = try #require(trial.coordinator.enchantmentProfile(
            of: Records.ring,
            on: .player
        ))
        #expect(profile.isWorn)
        #expect(profile.entries.map(\.magnitude) == [37])
        #expect(trial.inventory.copies(of: Records.ring, in: .player).first?.enchantment
            == FormID(EnchantingState.firstMadeID))
        #expect(trial.inventory.count(of: Gems.grandFilled, in: .player) == 0)
        #expect(trial.world.skillUses.map(\.amount) == [1])
    }

    /// Entry point 77 doubles the power: 30 * 2.5059 rounds down to 75.
    @Test func theEnchanterPerksScaleThePower() throws {
        let trial = try session(carrying: [Records.ring, Gems.grandFilled])
        trial.knowing([Records.healthBase])
        trial.world.perkFactors[.modEnchantmentPower] = 2
        try trial.coordinator.enchant(
            Records.ring, with: [trial.key(Records.healthBase)], gem: trial.gem(Gems.grandFilled)
        )
        let profile = try #require(trial.coordinator.enchantmentProfile(
            of: Records.ring,
            on: .player
        ))
        #expect(profile.entries.map(\.magnitude) == [75])
    }

    /// The grand soul gives the charge; at skill 100 a use costs 3 * 100^1.1 * 0.2929.
    @Test func aWeaponGetsTheSoulAsItsCharge() throws {
        let trial = try session(carrying: [Records.ironSword, Gems.grandFilled])
        trial.knowing([Records.fireBase])
        try trial.coordinator.enchant(
            Records.ironSword, with: [trial.key(Records.fireBase)], gem: trial.gem(Gems.grandFilled)
        )
        let charge = try #require(
            trial.coordinator.enchantmentCharge(of: Records.ironSword, on: .player)
        )
        #expect(charge.capacity == 3000)
        let fullCost = 3 * pow(Float(100), 1.1)
        let expected = fullCost * (1 - Float(0.5).squareRoot())
        #expect(abs(charge.costPerUse - expected) < 0.01)
        let profile = try #require(
            trial.coordinator.enchantmentProfile(of: Records.ironSword, on: .player)
        )
        #expect(profile.isContact)
        #expect(profile.entries.map(\.magnitude) == [12])
    }

    @Test func aBaseMustFitTheItem() throws {
        let trial = try session(carrying: [Records.ring, Gems.grandFilled])
        trial.knowing([Records.fireBase])
        let outcome = try trial.coordinator.enchant(
            Records.ring, with: [trial.key(Records.fireBase)], gem: trial.gem(Gems.grandFilled)
        )
        #expect(outcome == .refused(.baseDoesNotFit("Fire Damage")))
        #expect(trial.inventory.count(of: Gems.grandFilled, in: .player) == 1)
    }

    /// Entry point 80: Extra Effect sets two.
    @Test func extraEffectAllowsASecondBase() throws {
        let trial = try session(carrying: [Records.ring, Gems.grandFilled])
        trial.knowing([Records.healthBase, Records.magickaBase])
        let bases = [trial.key(Records.healthBase), trial.key(Records.magickaBase)]
        let gem = try trial.gem(Gems.grandFilled)
        #expect(trial.coordinator.enchant(Records.ring, with: bases, gem: gem)
            == .refused(.tooManyBases(allowed: 1)))
        trial.world.perkValues[.modAppliedEnchantmentsAllowed] = 2
        trial.coordinator.enchant(Records.ring, with: bases, gem: gem)
        let profile = try #require(trial.coordinator.enchantmentProfile(
            of: Records.ring,
            on: .player
        ))
        #expect(profile.entries.map(\.magnitude) == [37, 25])
    }
}
