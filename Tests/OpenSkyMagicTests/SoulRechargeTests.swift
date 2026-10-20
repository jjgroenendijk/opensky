// Recharging an enchanted weapon: from the smallest filled gem that fills it, with
// Soul Squeezer's bonus, keeping a reusable gem, and Soul Siphon's share of a kill.
// Records are synthetic (`SoulGemFixture.rechargePlugin`).

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import Testing

@MainActor
struct SoulRechargeTests {
    private typealias Gems = SoulGemFixture
    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x0900)

    @MainActor
    private struct Session {
        let coordinator: MagicCoordinator
        let world: FakeMagicWorld
        let inventory: FakeInventory

        var charge: Float {
            coordinator.enchantmentCharge(of: Gems.enchantedBlade, on: .player)?.remaining ?? -1
        }
    }

    /// The player wields the blade after `hits` hits and carries `gems`; `souls` fills
    /// one copy of a gem with a soul of that size.
    private func session(
        hits: Int, gems: [FormID], souls: [FormID: UInt8] = [:]
    ) throws -> Session {
        let file = try Gems.rechargePlugin()
        let plugin = ActiveEffectFixture.pluginName
        let enchantments = EnchantmentStore(plugins: [(plugin, file)])
        let inventory = FakeInventory(baselines: InventoryBaselineResolver.build(
            from: file,
            enchantments: ItemEnchantmentResolver(store: enchantments, pluginName: plugin)
        ))
        for item in [Gems.enchantedBlade] + gems {
            try inventory.add(item, count: 1, to: .player)
        }
        for (gem, soul) in souls {
            inventory.editCopy(of: gem, in: .player, where: { _ in true }, { $0.soul = soul })
        }
        let equipment = FakeHandEquipment()
        equipment.worn = [Gems.enchantedBlade]
        let world = FakeMagicWorld()
        world.inventory = inventory
        world.equipment = equipment
        world.holders[Self.victim] = ActorValueHolder(
            key: Self.victim, subject: .actor(base: FormID(0x0F01)), cell: nil
        )
        let coordinator = MagicCoordinator(world: world)
        coordinator.wireEffects(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(plugin, file)]),
            pluginName: plugin,
            conditionRegistry: ConditionFunctionRegistry()
        )
        coordinator.wireEnchantments(store: enchantments)
        let profile = try #require(coordinator.enchantmentProfile(of: Gems.enchantedBlade))
        coordinator.withEffects { runtime in
            let ledger = EnchantmentLedger(store: runtime.store, inventory: inventory)
            for _ in 0 ..< hits {
                ledger.spend(profile, on: .player)
            }
        }
        return Session(coordinator: coordinator, world: world, inventory: inventory)
    }

    /// Two hits leave 120 missing: the petty soul fills it, so the grand gem is kept.
    @Test func theSmallestGemThatFillsTheWeaponIsUsedUp() throws {
        let trial = try session(
            hits: 2, gems: [Gems.petty, Gems.grandFilled], souls: [Gems.petty: 1]
        )
        #expect(trial.charge == Gems.bladeCapacity - 2 * Gems.bladeCostPerUse)
        let outcome = trial.coordinator.rechargeEquippedWeapon()
        guard case let .recharged(item, gem, charge) = outcome else {
            Issue.record("expected a recharge, got \(outcome)")
            return
        }
        #expect(item == Gems.enchantedBlade)
        #expect(gem == Gems.petty)
        #expect(charge.remaining == Gems.bladeCapacity)
        #expect(trial.inventory.count(of: Gems.petty, in: .player) == 0)
        #expect(trial.inventory.count(of: Gems.grandFilled, in: .player) == 1)
        #expect(trial.inventory.copies(of: Gems.enchantedBlade, in: .player) == [.plain])
    }

    /// Ten hits leave 600 missing. The petty soul is all there is, and entry point 49
    /// doubles it here, so 500 goes back.
    @Test func soulSqueezerAddsToTheSoul() throws {
        let trial = try session(hits: 10, gems: [Gems.petty], souls: [Gems.petty: 1])
        trial.world.perkFactors[.modSoulGemRecharge] = 2
        trial.coordinator.rechargeEquippedWeapon()
        #expect(trial.charge == 1400)
        #expect(trial.world.perkOwners[.modSoulGemRecharge] == .player)
    }

    @Test func aReusableGemEmptiesAndStays() throws {
        let trial = try session(hits: 2, gems: [Gems.petty], souls: [Gems.petty: 1])
        trial.world.reusableGems = [Gems.petty]
        trial.coordinator.rechargeEquippedWeapon()
        #expect(trial.inventory.copies(of: Gems.petty, in: .player) == [.plain])
        #expect(trial.coordinator.rechargeEquippedWeapon() == .nothingToRecharge)
    }

    @Test func noFilledGemRechargesNothing() throws {
        let trial = try session(hits: 2, gems: [Gems.petty])
        #expect(trial.coordinator.rechargeEquippedWeapon() == .noFilledGem)
        #expect(trial.inventory.count(of: Gems.petty, in: .player) == 1)
    }

    /// A level 1 creature has a petty soul of 250; Soul Siphon's 0.05 of it is 12.5.
    @Test func soulSiphonFeedsTheKillersWeapon() throws {
        let trial = try session(hits: 10, gems: [])
        trial.coordinator.noteDeath(of: Self.victim, killer: .player)
        #expect(trial.charge == 900)
        trial.world.perkValues[.modSoulPctCapturedToWeapon] = 0.05
        trial.coordinator.noteDeath(of: Self.victim, killer: .player)
        #expect(trial.charge == 912.5)
        #expect(trial.world.perkOwners[.modSoulPctCapturedToWeapon] == .player)
    }
}
