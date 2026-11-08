// An enchanted weapon's charge lives on the copy the owner holds: a hit spends the
// best copy, a recharge fills it again, and a charge kept per base item moves onto
// the copy. Records are synthetic (`EnchantmentRuntimeFixture`).

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct EnchantmentChargeCopyTests {
    private let blade = FormID(EnchantmentRuntimeFixture.enchantedBlade)

    private func inventory(_ world: EnchantmentRuntimeFixture.World, blades: Int32) throws
        -> InventoryRuntime
    {
        let baselines = try InventoryBaselineResolver.build(
            from: EnchantmentRuntimeFixture.plugin()
        )
        let inventory = InventoryRuntime(store: world.store, baselines: baselines)
        try inventory.add(blade, count: blades, to: .player)
        return inventory
    }

    /// Two blades: one hit spends the first copy only, and the other stays full.
    @Test func aHitSpendsOneCopy() throws {
        let world = try EnchantmentRuntimeFixture.world()
        let profile = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        let inventory = try inventory(world, blades: 2)
        let ledger = EnchantmentLedger(store: world.store, inventory: inventory)
        let after = try #require(ledger.spend(profile, on: .player))
        #expect(after.remaining == 72)
        #expect(inventory.copies(of: blade, in: .player) == [ItemCopy(charge: 72), .plain])
        #expect(world.store.component(EnchantedItemState.self, for: .player) == nil)
        #expect(ledger.charge(of: profile, on: .player).remaining == 72)
    }

    /// A recharge stops at the capacity, and a full copy is plain again.
    @Test func aRechargeFillsTheCopyUpToItsCapacity() throws {
        let world = try EnchantmentRuntimeFixture.world()
        let profile = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        let inventory = try inventory(world, blades: 1)
        let ledger = EnchantmentLedger(store: world.store, inventory: inventory)
        ledger.spend(profile, on: .player)
        ledger.spend(profile, on: .player)
        #expect(ledger.recharge(profile, by: 9, on: .player).remaining == 63)
        #expect(ledger.recharge(profile, by: 1000, on: .player).remaining == profile.capacity)
        #expect(inventory.copies(of: blade, in: .player) == [.plain])
    }

    /// A charge recorded per base item, as an older save holds it, is read and then
    /// moves onto the copy at the next hit.
    @Test func aChargeKeptPerItemMovesOntoTheCopy() throws {
        let world = try EnchantmentRuntimeFixture.world()
        let profile = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        let inventory = try inventory(world, blades: 1)
        world.store.set(EnchantedItemState(charges: [blade.rawValue: 54]), for: .player)
        let ledger = EnchantmentLedger(store: world.store, inventory: inventory)
        #expect(ledger.charge(of: profile, on: .player).remaining == 54)
        ledger.spend(profile, on: .player)
        #expect(inventory.copies(of: blade, in: .player) == [ItemCopy(charge: 36)])
        #expect(world.store.component(EnchantedItemState.self, for: .player) == nil)
    }
}
