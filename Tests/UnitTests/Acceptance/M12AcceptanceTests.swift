// M12 acceptance (issue #180): the first repeatable gameplay loop, proved end
// to end in one scripted run with no shortcut anywhere in the middle.
//
// Grant, take, transfer, equip, buy, sell, drop, save, load — each step against
// the real runtimes issues #175 to #179 landed, over one synthetic plugin and
// one synthetic reference index. Every step asserts the accounting, not just
// that the call returned: item totals across the owners involved, gold across
// the pair, the world-state deltas the step wrote, and which cell they were
// attributed to.
//
// The gate's pixel evidence is `M12AcceptanceRenderTests`, which is gated on a
// Metal device; everything here runs without one, so the loop still stands on a
// device-less runner.

import Foundation
@testable import opensky
import Testing

@MainActor
struct M12AcceptanceTests {
    private typealias Chain = M12AcceptanceChain
    private typealias Fixture = InventoryBaselineFixture

    /// What the merchant is stocked with before trading opens. The empty-chest
    /// base is used so the stock is exactly what the gate granted, with no
    /// CNTO baseline underneath it to confuse the arithmetic.
    private static let merchantGold: Int32 = 500
    private static let merchantSwords: Int32 = 2

    /// The slot the save/load step writes. Named for the gate so a stray file
    /// in a developer's saves directory says where it came from.
    private static let slot = "m12-acceptance"

    // MARK: - The loop

    /// The gate itself. One session walks the whole loop and every step is
    /// checked before the next one runs, so a failure names the step rather
    /// than leaving an end state to reverse-engineer.
    @Test("the whole take-transfer-equip-trade-drop loop conserves and persists")
    func theGameplayLoopRunsEndToEnd() throws {
        let chain = try Chain()
        let inventory = chain.runtime.inventory

        // Step 1 — grant. The only step that creates items, which is why the
        // total is captured after it rather than before.
        try inventory.add(Fixture.gold, count: 200, to: chain.player)
        try inventory.add(Fixture.cuirass, count: 1, to: chain.player)
        try inventory.add(Fixture.sword, count: Self.merchantSwords, to: chain.merchant)
        try inventory.add(Fixture.gold, count: Self.merchantGold, to: chain.merchant)
        // The actor needs something to put on: an equip of what an owner does
        // not hold is a typed failure, not a silent no-op.
        try inventory.add(Fixture.sword, count: 1, to: chain.guardActor)
        // The starting totals are read rather than assumed: the chest's CNTO
        // baseline resolves a leveled list, so how much it holds is the
        // fixture's answer to give, not this test's. The loose sword is added
        // by hand because it is in the world, not in an inventory.
        let swordsInWorld = Self.total(chain, of: Fixture.sword) + 1
        let goldInWorld = Self.totalGold(chain)
        #expect(inventory.goldCount(of: chain.player) == 200)
        #expect(swordsInWorld >= Self.merchantSwords + 2)

        // Step 2 — take the loose sword. It leaves the world and enters the
        // player, and the reference is marked deleted in its own cell.
        let outcome = try chain.runtime.take(
            Chain.take(Chain.looseSwordReference, base: Fixture.sword)
        )
        #expect(outcome.item == Fixture.sword)
        #expect(outcome.count == 1)
        #expect(inventory.count(of: Fixture.sword, in: chain.player) == 1)
        #expect(chain.store.component(
            ReferenceDeletionState.self, for: Chain.key(Chain.looseSwordReference)
        )?.isDeleted == true)
        // Two cell-attributed writes so far: the merchant's stock and the
        // actor's. The player belongs to no cell, so their stack is
        // deliberately unattributed, and the deletion makes it three.
        #expect(chain.store.dirtyCount(in: Chain.cell) == 3)
        #expect(chain.store.unattributedDirtyCount == 1)

        let chestLockpicks = try Self.transferThroughTheContainer(chain)
        try Self.equipOnTheActor(chain)

        try Self.tradeWithTheMerchant(chain, playerGold: 200)

        // Step 7 — drop. One item leaves the player and one spawned reference
        // appears in the cell they are standing in.
        let dropped = try chain.runtime.drop(
            Fixture.lockpick,
            count: 1,
            at: DropPlacement(location: Chain.cell, position: SIMD3(10, 20, 30))
        )
        #expect(inventory.count(of: Fixture.lockpick, in: chain.player) == chestLockpicks - 1)
        let spawn = try #require(
            chain.store.component(ReferenceSpawnState.self, for: dropped)
        )
        #expect(spawn.base == Fixture.lockpick)
        #expect(spawn.count == 1)
        #expect(spawn.location == Chain.cell)

        // The accounting that makes the loop a loop: after everything above,
        // every sword and every coin the session started with is still
        // somewhere, and nothing was created after the grant.
        try Self.expectConserved(
            chain, swords: swordsInWorld, gold: goldInWorld, dropped: dropped
        )

        // Steps 8 and 9 — save and load. A brand-new store restored from the
        // file is in the identical end state, allocator position included.
        let restored = try Self.roundTrip(chain.store)
        #expect(restored.snapshot() == chain.store.snapshot())
        let restoredInventory = try InventoryRuntime(
            store: restored, baselines: Fixture.resolver()
        )
        #expect(restoredInventory.goldCount(of: chain.player)
            == inventory.goldCount(of: chain.player))
        #expect(restoredInventory.count(of: Fixture.lockpick, in: chain.player)
            == chestLockpicks - 1)
        #expect(restoredInventory.inventory(of: chain.guardActor).equipped
            == chain.equipment.equipped(on: chain.guardActor))
        // The world survived too: the taken reference is still deleted and the
        // dropped one is still spawned where it landed.
        #expect(restored.component(
            ReferenceDeletionState.self, for: Chain.key(Chain.looseSwordReference)
        )?.isDeleted == true)
        #expect(restored.component(ReferenceSpawnState.self, for: dropped) == spawn)
    }

    // MARK: - Steps

    /// Step 3 — a container session moving items both ways.
    ///
    /// The chest's CNTO baseline materializes on the first write, and the
    /// starting counts are read rather than assumed: the baseline resolves a
    /// leveled list, so how much it holds is the fixture's answer to give.
    ///
    /// - Returns: how many lockpicks the chest started with, which the drop
    ///   step later takes one of.
    @discardableResult
    private static func transferThroughTheContainer(_ chain: Chain) throws -> Int32 {
        let inventory = chain.runtime.inventory
        let session = try chain.runtime.openContainer(
            Chain.search(Chain.chestReference, base: Fixture.chest)
        )
        #expect(session.isOpen)
        let chestLockpicks = inventory.count(of: Fixture.lockpick, in: chain.chest)
        #expect(chestLockpicks == 3)
        let chestCuirasses = inventory.count(of: Fixture.cuirass, in: chain.chest)
        let cuirassesAcross = total(chain, of: Fixture.cuirass)

        try session.deposit(Fixture.cuirass, count: 1)
        #expect(inventory.count(of: Fixture.cuirass, in: chain.player) == 0)
        #expect(inventory.count(of: Fixture.cuirass, in: chain.chest) == chestCuirasses + 1)
        // A transfer moves, it does not create: the two sides changed and the
        // sum across every holder did not.
        #expect(total(chain, of: Fixture.cuirass) == cuirassesAcross)

        try session.take(Fixture.cuirass, count: 1)
        try session.take(Fixture.lockpick, count: chestLockpicks)
        #expect(inventory.count(of: Fixture.cuirass, in: chain.player) == 1)
        #expect(inventory.count(of: Fixture.lockpick, in: chain.player) == chestLockpicks)
        #expect(inventory.count(of: Fixture.lockpick, in: chain.chest) == 0)
        session.close()
        #expect(!session.isOpen)
        return chestLockpicks
    }

    /// Step 4 — equipping on the actor an equip is visible on. The write is
    /// attributed to that actor's cell, which is what queues its rebuild.
    private static func equipOnTheActor(_ chain: Chain) throws {
        let change = try chain.equipment.equip(Fixture.sword, on: chain.guardActor)
        #expect(change.changed)
        #expect(chain.equipment.equipped(on: chain.guardActor).contains(Fixture.sword))
        #expect(chain.store.component(
            ReferenceInventoryState.self, for: chain.guardActor.key
        )?.equipped.contains(Fixture.sword) == true)

        // A conflicting piece displaces rather than stacks: the greatsword
        // claims both hands, so the one-handed sword comes off.
        try chain.runtime.inventory.add(Fixture.greatsword, count: 1, to: chain.guardActor)
        let displacing = try chain.equipment.equip(Fixture.greatsword, on: chain.guardActor)
        #expect(displacing.unequipped == [Fixture.sword])
        #expect(!chain.equipment.equipped(on: chain.guardActor).contains(Fixture.sword))
    }

    /// Steps 5 and 6 — buying a sword and selling the same one straight back.
    /// Gold goes one way and the item the other in a single write each time,
    /// and the merchant pays less than it charged, which is the whole point of
    /// the price factor.
    private static func tradeWithTheMerchant(_ chain: Chain, playerGold: Int32) throws {
        let inventory = chain.runtime.inventory
        let barter = chain.barter
        let buyPrice = barter.buyPrice(of: Fixture.sword)
        #expect(buyPrice > 0)
        let bought = try barter.buy(Fixture.sword)
        #expect(bought.gold == buyPrice)
        #expect(inventory.goldCount(of: chain.player) == playerGold - buyPrice)
        #expect(inventory.goldCount(of: chain.merchant) == merchantGold + buyPrice)

        let sellPrice = barter.sellPrice(of: Fixture.sword)
        #expect(sellPrice < buyPrice)
        let sold = try barter.sell(Fixture.sword)
        #expect(sold.gold == sellPrice)
        #expect(inventory.goldCount(of: chain.player) == playerGold - buyPrice + sellPrice)
    }

    // MARK: - Ownership

    /// `XOWN` and `XRNK` survive the decode and reach the panel's readout, and
    /// an unowned reference reads as unowned rather than as owned by form zero.
    @Test("the gate reports who owns what the loop takes")
    func ownershipReachesTheReadout() throws {
        let chain = try Chain()
        let owned = try #require(
            chain.references.referenceEntry(formID: Chain.looseSwordReference)?.placedReference
        )
        #expect(owned.owner == Chain.ownerActor)
        #expect(owned.ownerFactionRank == 2)

        let readout = ReferenceOwnershipReadout(
            name: "Iron Sword",
            reference: Chain.looseSwordReference,
            owner: owned.owner,
            factionRank: owned.ownerFactionRank,
            isTheft: true
        )
        #expect(readout.isOwned)
        let text = InventoryEquipmentReadout.ownershipText(for: Self.snapshot(readout))
        #expect(text.contains("taking this is theft."))
        #expect(text.contains("Faction rank required: 2"))

        let unowned = try #require(
            chain.references.referenceEntry(formID: Chain.chestReference)?.placedReference
        )
        #expect(unowned.owner == nil)
        #expect(unowned.ownerFactionRank == nil)
    }

    // MARK: - Refusals

    /// The loop's refusals are ordinary outcomes that write nothing: a merchant
    /// with an empty purse still sells its stock, and a player who cannot pay
    /// keeps their gold.
    @Test("a refused trade leaves both sides exactly as they were")
    func refusedTradesWriteNothing() throws {
        let chain = try Chain()
        let inventory = chain.runtime.inventory
        try inventory.add(Fixture.sword, count: 1, to: chain.merchant)
        try inventory.add(Fixture.cuirass, count: 1, to: chain.player)
        let before = chain.store.snapshot()
        let barter = chain.barter

        // No gold on either side: the player cannot buy and the merchant
        // cannot pay for what it is offered.
        #expect(throws: BarterError.self) { try barter.buy(Fixture.sword) }
        #expect(throws: BarterError.self) { try barter.sell(Fixture.cuirass) }
        #expect(chain.store.snapshot() == before)

        // Buying more than the merchant stocks, and selling what the player
        // does not carry, are refusals of the same kind.
        try inventory.add(Fixture.gold, count: 10000, to: chain.player)
        #expect(throws: BarterError.self) { try barter.buy(Fixture.sword, count: 5) }
        #expect(throws: BarterError.self) { try barter.sell(Fixture.helmet) }
        #expect(inventory.count(of: Fixture.sword, in: chain.merchant) == 1)
        #expect(inventory.goldCount(of: chain.player) == 10000)
    }

    /// Equipping something the owner does not hold is a typed failure that
    /// writes nothing, so a failed equip cannot leave a phantom in the set.
    /// The guard's plugin outfit already dresses it, so the item chosen here is
    /// one the outfit does not include — the gauntlets, which contest nothing.
    @Test("a refused equip leaves the equipped set untouched")
    func refusedEquipWritesNothing() throws {
        let chain = try Chain()
        let before = chain.store.snapshot()
        #expect(throws: EquipmentError.self) {
            try chain.equipment.equip(Fixture.gauntlets, on: chain.guardActor)
        }
        #expect(chain.store.snapshot() == before)
        #expect(!chain.equipment.equipped(on: chain.guardActor).contains(Fixture.gauntlets))
    }

    // MARK: - Helpers

    /// Every sword and every coin the session created is accounted for across
    /// the player, the chest, the merchant, the actor and the ground.
    private static func expectConserved(
        _ chain: Chain,
        swords: Int32,
        gold: Int32,
        dropped: ReferenceKey
    ) throws {
        // The loose sword is now carried rather than lying in the world, so
        // the same number is expected in inventories as was in the world.
        #expect(total(chain, of: Fixture.sword) == swords)
        // Gold is only ever moved after the grant, never made.
        #expect(totalGold(chain) == gold)

        // The one thing on the ground is the dropped lockpick and nothing else.
        let spawns = chain.store.snapshot().entries.filter {
            $0.delta.component(ReferenceSpawnState.self) != nil
        }
        #expect(spawns.map(\.key) == [dropped])
    }

    /// Every holder the loop touches. The player is first because they are
    /// the one owner with no cell.
    private static func holders(_ chain: Chain) -> [InventoryHolder] {
        [chain.player, chain.chest, chain.merchant, chain.guardActor]
    }

    private static func total(_ chain: Chain, of item: FormID) -> Int32 {
        holders(chain).reduce(Int32(0)) {
            $0 + chain.runtime.inventory.count(of: item, in: $1)
        }
    }

    private static func totalGold(_ chain: Chain) -> Int32 {
        holders(chain).reduce(Int32(0)) { $0 + chain.runtime.inventory.goldCount(of: $1) }
    }

    /// Writes the store to a real save slot in a temporary directory and reads
    /// it back into a brand-new store.
    private static func roundTrip(_ store: WorldStateStore) throws -> WorldStateStore {
        let directory = URL.temporaryDirectory
            .appending(path: "opensky-m12-\(UInt64(store.snapshot().sequence))-tests")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let saves = OpenSkySaveStore(directory: directory)
        try saves.save(
            snapshot: store.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            toSlot: slot
        )
        let file = try saves.load(
            slot: slot, verifyingAgainst: OpenSkySaveFixture.fingerprint
        )
        let restored = WorldStateStore()
        restored.restore(from: file.snapshot)
        return restored
    }

    private static func snapshot(
        _ ownership: ReferenceOwnershipReadout
    ) -> InventoryEquipmentSnapshot {
        InventoryEquipmentSnapshot(
            isAvailable: true,
            hasOpenContainer: false,
            openContainerName: nil,
            playerStacks: [],
            playerGold: 0,
            playerWeight: 0,
            containerStacks: [],
            containerGold: 0,
            targetOwnership: ownership,
            equipTarget: .nearestActor,
            equipInspection: .unresolved,
            enchantmentCache: .empty,
            lastActionText: "No grant yet."
        )
    }
}
