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
    typealias Records = EnchantingFixture
    typealias Gems = SoulGemFixture

    @MainActor
    struct Session {
        let coordinator: MagicCoordinator
        let world: FakeMagicWorld
        let inventory: FakeInventory

        func key(_ id: FormID) -> ReferenceKey {
            .plugin(name: ActiveEffectFixture.pluginName.lowercased(), objectID: id.rawValue)
        }

        func gem(_ item: FormID) throws -> SoulGemCandidate {
            let snapshot = coordinator.enchantingReadout.enchantingSnapshot
            return try #require(snapshot.gems.first { $0.gem.item == item }?.gem)
        }

        /// The player knows `bases` already.
        func knowing(_ bases: [FormID]) {
            coordinator.withEffects { runtime in
                runtime.store.set(EnchantingState(known: bases.map(key)), for: .player)
            }
        }
    }

    func session(skill: Float = 100, carrying items: [FormID]) throws -> Session {
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
        #expect(abs(EnchantingSettings.vanilla.rechargeExperience(charge: 3000) - 0.6) < 0.000_01)
    }

    @Test func lowSkillStillRaisesThePowerALittle() {
        // Below skill 14 the second term holds at 0.01: 1 + 0.25 x 0.1 x 0.01.
        #expect(abs(EnchantingRules.skillMultiplier(10) - 1.000_25) < 0.000_001)
        // A doubled factor doubles the gain: 1 + 0.5 x 86 / 85.
        #expect(abs(EnchantingRules.skillMultiplier(100, factor: 1.5) - 1.505_88) < 0.000_01)
    }

    /// The game keeps the full maximum for any soul: a petty soul only gives less charge.
    @Test func aSmallSoulKeepsAWeaponsFullPower() {
        let input = EnchantingInput(skill: 0, soul: .petty, bases: [EnchantingBase(cost: 100)])
        let scale = EnchantingRules.weapon(input)
        #expect(scale.capacity == 250)
        #expect(scale.powers == [1])
        // 3 x 100^1.1 = 475.47, fraction dropped.
        #expect(scale.costPerUse == 475)
        #expect(scale.uses == 0)
    }

    /// The page's example: Fire Damage with magnitude 10 and cost 0.9 x 10^1.1, at
    /// Enchanting 15 with a grand soul.
    private func fireSword(chosen: Int?) -> EnchantingInput {
        var input = EnchantingInput(
            skill: 15, soul: .grand, bases: [EnchantingBase(cost: 0.9 * pow(10, 1.1))]
        )
        input.baseMagnitude = 10
        input.chosen = chosen
        return input
    }

    @Test func theSliderRunsFromOneToTheMaximumInStepsOfOne() throws {
        let slider = try #require(EnchantingRules.slider(fireSword(chosen: nil)))
        #expect(slider == EnchantingSlider(maximum: 10, step: 1, value: 10))
        #expect(EnchantingRules.slider(fireSword(chosen: 40))?.value == 10)
        #expect(EnchantingRules.slider(fireSword(chosen: -3))?.value == 1)
    }

    @Test func theChosenShareSetsTheCostAndTheUses() {
        let full = EnchantingRules.weapon(fireSword(chosen: 10))
        #expect(full.costPerUse == 31)
        #expect(full.uses == 95)
        #expect(full.capacity == 3000)
        let half = EnchantingRules.weapon(fireSword(chosen: 5))
        #expect(half.costPerUse == 14)
        #expect(half.uses == 204)
        #expect(abs(half.powers[0] - full.powers[0] / 2) < 0.000_1)
    }

    @Test func theStepGrowsWithTheMaximum() {
        #expect([30, 31, 60, 61, 120, 121].map(EnchantingRules.sliderStep) == [1, 2, 2, 5, 5, 10])
    }

    @Test func aMaximumOfOneShowsNoSlider() {
        var input = fireSword(chosen: nil)
        input.baseMagnitude = 1
        #expect(EnchantingRules.slider(input) == nil)
    }

    /// The made sword's value: 25 + 0.12 x 3000 + 8 x 31 = 633. Apparel adds its cost.
    @Test func aMadeEnchantmentAddsTheGamesValue() {
        let made = MadeEnchantment(
            bases: [.player], powers: [1], capacity: 3000, costPerUse: 31, name: "Fire"
        )
        #expect(25 + made.addedValue(isWeapon: true, settings: .vanilla) == 633)
        #expect(made.addedValue(isWeapon: false, settings: .vanilla) == 31)
    }

    /// Apparel at a common soul: the maximum times a third, at least 1.
    @Test func apparelTakesTheSoulsShareOfTheMaximum() {
        var input = EnchantingInput(skill: 0, soul: .common, bases: [EnchantingBase(cost: 10)])
        input.baseMagnitude = 30
        #expect(abs(EnchantingRules.apparel(input).powers[0] * 30 - 10) < 0.001)
        input.baseMagnitude = 2
        #expect(abs(EnchantingRules.apparel(input).powers[0] * 2 - 1) < 0.001)
    }

    @Test func disenchantingTeachesTheRootBaseAndDestroysTheItem() throws {
        let trial = try session(carrying: [Records.fireSword])
        let outcome = trial.coordinator.enchantingRecords.disenchant(Records.fireSword)
        guard case .learned = outcome else {
            Issue.record("expected a learned base, got \(outcome)")
            return
        }
        #expect(trial.coordinator.enchantingRecords.enchantingState
            .known == [trial.key(Records.fireBase)])
        #expect(trial.inventory.count(of: Records.fireSword, in: .player) == 0)
        // 100 + 0.12 * 1000 + 8 * 30 = 460 gold, 360 of it the enchantment's.
        #expect(trial.world.skillUses.map(\.amount) == [0.9])
    }

    @Test func aKnownBaseIsNotLearnedTwice() throws {
        let trial = try session(carrying: [Records.fireSword])
        trial.knowing([Records.fireBase])
        #expect(trial.coordinator.enchantingRecords
            .disenchant(Records.fireSword) == .refused(.alreadyKnown))
        #expect(trial.inventory.count(of: Records.fireSword, in: .player) == 1)
    }

    /// Skill 100 and a grand soul: 30 * 1.2529 rounds down to 37, and the gem is spent.
    @Test func aRingTakesAnApparelBaseScaledBySkillAndSoul() throws {
        let trial = try session(carrying: [Records.ring, Gems.grandFilled])
        trial.knowing([Records.healthBase])
        let outcome = try trial.coordinator.enchantingTable.enchant(
            Records.ring, with: [trial.key(Records.healthBase)], gem: trial.gem(Gems.grandFilled)
        )
        guard case .enchanted = outcome else {
            Issue.record("expected an enchanted ring, got \(outcome)")
            return
        }
        #expect(trial.coordinator.journalStat("Magic Items Made") == 1)
        let profile = try #require(trial.coordinator.weaponEnchantments.enchantmentProfile(
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
        try trial.coordinator.enchantingTable.enchant(
            Records.ring, with: [trial.key(Records.healthBase)], gem: trial.gem(Gems.grandFilled)
        )
        let profile = try #require(trial.coordinator.weaponEnchantments.enchantmentProfile(
            of: Records.ring,
            on: .player
        ))
        #expect(profile.entries.map(\.magnitude) == [75])
    }

    /// The grand soul gives the charge; at skill 100 a use costs 3 * 100^1.1 * 0.2929,
    /// stored with its fraction dropped.
    @Test func aWeaponGetsTheSoulAsItsCharge() throws {
        let trial = try session(carrying: [Records.ironSword, Gems.grandFilled])
        trial.knowing([Records.fireBase])
        try trial.coordinator.enchantingTable.enchant(
            Records.ironSword, with: [trial.key(Records.fireBase)], gem: trial.gem(Gems.grandFilled)
        )
        let charge = try #require(
            trial.coordinator.weaponEnchantments.enchantmentCharge(
                of: Records.ironSword,
                on: .player
            )
        )
        #expect(charge.capacity == 3000)
        let fullCost = 3 * pow(Float(100), 1.1)
        let expected = (fullCost * (1 - Float(0.5).squareRoot())).rounded(.down)
        #expect(charge.costPerUse == expected)
        let profile = try #require(
            trial.coordinator.weaponEnchantments.enchantmentProfile(
                of: Records.ironSword,
                on: .player
            )
        )
        #expect(profile.isContact)
        #expect(profile.entries.map(\.magnitude) == [12])
    }

    @Test func aBaseMustFitTheItem() throws {
        let trial = try session(carrying: [Records.ring, Gems.grandFilled])
        trial.knowing([Records.fireBase])
        let outcome = try trial.coordinator.enchantingTable.enchant(
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
        #expect(trial.coordinator.enchantingTable.enchant(Records.ring, with: bases, gem: gem)
            == .refused(.tooManyBases(allowed: 1)))
        trial.world.perkValues[.modAppliedEnchantmentsAllowed] = 2
        trial.coordinator.enchantingTable.enchant(Records.ring, with: bases, gem: gem)
        let profile = try #require(trial.coordinator.weaponEnchantments.enchantmentProfile(
            of: Records.ring,
            on: .player
        ))
        #expect(profile.entries.map(\.magnitude) == [37, 25])
    }

    @Test func theEnchanterListsTheCarriedItemsAndDisenchantsInTheGamesWords() throws {
        let trial = try session(carrying: [Records.fireSword, Records.ring, Gems.grandFilled])
        let enchanter = trial.coordinator.enchanter
        let choices = enchanter.enchanterChoices
        #expect(choices.disenchantable.map(\.id) == [Records.fireSword])
        #expect(choices.enchantable.map(\.id) == [Records.ring])
        #expect(choices.gems.map(\.item) == [Gems.grandFilled])
        #expect(enchanter.disenchant(Records.fireSword).done)
        #expect(!enchanter.disenchant(Records.fireSword).done)
    }

    @Test func anIncompleteSelectionIsRefusedAndACompleteOneEnchants() throws {
        let trial = try session(carrying: [Records.ring, Gems.grandFilled])
        trial.knowing([Records.healthBase])
        let enchanter = trial.coordinator.enchanter
        var selection = EnchanterSelection()
        #expect(enchanter.refusal(of: selection) != nil)
        #expect(!enchanter.enchant(selection).done)
        selection.item = Records.ring
        selection.bases = [trial.key(Records.healthBase)]
        selection.gem = enchanter.enchanterChoices.gems.first
        #expect(enchanter.refusal(of: selection) == nil)
        #expect(enchanter.enchant(selection).done)
    }

    @Test func withoutAGameTheEnchanterListsNothing() {
        let enchanter = MagicCoordinator(world: FakeMagicWorld()).enchanter
        #expect(enchanter.enchanterChoices == EnchanterChoices())
        #expect(!enchanter.disenchant(Records.fireSword).done)
    }
}
