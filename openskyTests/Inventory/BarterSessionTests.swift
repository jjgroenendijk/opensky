// Merchant transactions (issue #179): conservation of gold and of items across
// a buy and a sell, the two insufficient-funds refusals, and the journalling
// that makes a transaction survive a save.
//
// Reuses the synthetic plugin `InventoryBaselineFixture` builds and the
// reference harness `WorldItemRuntimeTests` builds, so a merchant is an
// ordinary container reference here exactly as it is in the engine.

import Foundation
@testable import opensky
import Testing

@MainActor
struct BarterSessionTests {
    private typealias Fixture = InventoryBaselineFixture
    private typealias Parent = WorldItemRuntimeTests

    /// `@MainActor` because `InventoryRuntime` is, and the convenience below
    /// reaches into it.
    @MainActor
    private struct Trading {
        let harness: Parent.Harness
        let session: BarterSession
        let merchant: InventoryHolder

        var inventory: InventoryRuntime {
            harness.runtime.inventory
        }
    }

    /// A merchant holding the fixture chest's baseline — 3 lockpicks, 1 gold
    /// and the one cuirass its leveled entry resolves to — topped up with two
    /// more cuirasses and a purse, facing a player with gold and a sword.
    private func openShop(
        merchantGold: Int32 = 1000,
        playerGold: Int32 = 1000
    ) throws -> Trading {
        let harness = try Parent.standardHarness()
        let container = try harness.runtime.openContainer(Parent.interaction(
            reference: Parent.chestReference, base: Fixture.chest, action: .search
        )).container
        let inventory = harness.runtime.inventory
        try inventory.add(Fixture.cuirass, count: 2, to: container)
        try inventory.add(Fixture.sword, count: 1, to: .player)
        // Zero is not a stack size: a purse of nothing is simply not added, and
        // the chest's own CNTO gold is then the merchant's whole purse.
        if merchantGold > 0 {
            try inventory.add(inventory.goldFormID, count: merchantGold, to: container)
        }
        if playerGold > 0 {
            try inventory.add(inventory.goldFormID, count: playerGold, to: .player)
        }
        return Trading(
            harness: harness,
            session: BarterSession(
                runtime: harness.runtime, merchant: container, pricing: .vanilla
            ),
            merchant: container
        )
    }

    /// Everything either owner holds, so conservation can be asserted over the
    /// pair rather than over one side.
    private func totals(_ shop: Trading) -> [FormID: Int32] {
        var totals: [FormID: Int32] = [:]
        for holder in [shop.merchant, InventoryHolder.player] {
            for stack in shop.inventory.inventory(of: holder).stacks {
                totals[stack.item, default: 0] += stack.count
            }
        }
        return totals
    }

    // MARK: - Buying

    @Test func buyingMovesTheItemOneWayAndTheGoldTheOther() throws {
        let shop = try openShop()
        let before = totals(shop)
        // IronCuirass is worth 125; at the vanilla factor of 3.105 that is 388.
        #expect(shop.session.buyPrice(of: Fixture.cuirass) == 388)

        let bought = try shop.session.buy(Fixture.cuirass)

        #expect(bought == BarterTransaction(
            kind: .buy, item: Fixture.cuirass, count: 1, gold: 388
        ))
        #expect(shop.inventory.count(of: Fixture.cuirass, in: .player) == 1)
        #expect(shop.inventory.count(of: Fixture.cuirass, in: shop.merchant) == 2)
        #expect(shop.session.playerGold == 1000 - 388)
        #expect(shop.session.merchantGold == 1000 + 388 + 1, "the chest's own gold stays")
        #expect(totals(shop) == before, "buying created or destroyed something")
    }

    @Test func buyingMoreThanTheMerchantStocksWritesNothing() throws {
        let shop = try openShop()
        let before = totals(shop)
        #expect(throws: BarterError.notStocked(item: Fixture.cuirass, wanted: 5, available: 3)) {
            try shop.session.buy(Fixture.cuirass, count: 5)
        }
        #expect(totals(shop) == before)
    }

    @Test func aPlayerWhoCannotPayIsRefusedAndKeepsTheirGold() throws {
        let shop = try openShop(playerGold: 100)
        let before = totals(shop)
        #expect(throws: BarterError.playerCannotAfford(price: 388, gold: 100)) {
            try shop.session.buy(Fixture.cuirass)
        }
        #expect(totals(shop) == before)
        #expect(shop.inventory.count(of: Fixture.cuirass, in: .player) == 0)
    }

    // MARK: - Selling

    @Test func sellingMovesTheItemToTheMerchantAndGoldToThePlayer() throws {
        let shop = try openShop()
        let before = totals(shop)
        // IronSword is worth 25; 25 / 3.105 rounds to 8.
        #expect(shop.session.sellPrice(of: Fixture.sword) == 8)

        let sold = try shop.session.sell(Fixture.sword)

        #expect(sold == BarterTransaction(kind: .sell, item: Fixture.sword, count: 1, gold: 8))
        #expect(shop.inventory.count(of: Fixture.sword, in: .player) == 0)
        #expect(shop.session.playerGold == 1008)
        #expect(shop.session.merchantGold == 1000 + 1 - 8)
        #expect(totals(shop) == before, "selling created or destroyed something")
    }

    @Test func sellingWhatThePlayerDoesNotCarryWritesNothing() throws {
        let shop = try openShop()
        let before = totals(shop)
        #expect(throws: BarterError.notCarried(item: Fixture.helmet, wanted: 1, available: 0)) {
            try shop.session.sell(Fixture.helmet)
        }
        #expect(totals(shop) == before)
    }

    /// The zero-gold merchant named in the issue: it can buy nothing and still
    /// sell everything.
    @Test func aMerchantWithNoGoldBuysNothingAndSellsEverything() throws {
        let shop = try openShop(merchantGold: 0)
        // The fixture chest's own CNTO gold is the merchant's whole purse.
        #expect(shop.session.merchantGold == 1)
        #expect(throws: BarterError.merchantCannotAfford(price: 8, gold: 1)) {
            try shop.session.sell(Fixture.sword)
        }
        // Buying from it still works, and its purse grows by what was paid.
        try shop.session.buy(Fixture.cuirass)
        #expect(shop.session.merchantGold == 389)
    }

    /// A worthless item trades for nothing rather than being untradeable: the
    /// zero-gold leg of the exchange is skipped, not rejected.
    @Test func aZeroPriceItemStillChangesHands() throws {
        let shop = try openShop(merchantGold: 0)
        try shop.harness.runtime.inventory.add(Fixture.lockpick, count: 1, to: .player)
        // Lockpick is worth 5; 5 / 3.105 rounds to 2, so drop it to a free item
        // by pricing at a factor no gold can meet.
        let free = BarterSession(
            runtime: shop.harness.runtime,
            merchant: shop.merchant,
            pricing: BarterPricing(barterMin: 1e6, barterMax: 1e6)
        )
        #expect(free.sellPrice(of: Fixture.lockpick) == 0)
        let sold = try free.sell(Fixture.lockpick)
        #expect(sold.gold == 0)
        #expect(shop.inventory.count(of: Fixture.lockpick, in: .player) == 0)
        #expect(
            shop.inventory.count(of: Fixture.lockpick, in: shop.merchant) == 4,
            "the merchant's three became four for free"
        )
    }

    @Test func nonPositiveCountsAreRejected() throws {
        let shop = try openShop()
        #expect(throws: BarterError.nonPositiveCount(0)) {
            try shop.session.buy(Fixture.cuirass, count: 0)
        }
        #expect(throws: BarterError.nonPositiveCount(-2)) {
            try shop.session.sell(Fixture.sword, count: -2)
        }
    }

    // MARK: - Journalling

    /// Both owners' inventories are written through `WorldStateStore`, so a
    /// transaction lands in the journal and therefore in the save, exactly as
    /// an ordinary transfer does.
    @Test func everyTransactionIsJournalledForBothOwners() throws {
        let shop = try openShop()
        let before = shop.harness.store.nextJournalSequence
        try shop.session.buy(Fixture.cuirass)
        #expect(
            shop.harness.store.nextJournalSequence == before + 2,
            "one journal entry per owner, buyer then seller"
        )
        let dirty = shop.harness.store.snapshot().entries.map(\.key)
        #expect(dirty.contains(.player))
        #expect(dirty.contains(shop.merchant.key))
    }

    /// A refused transaction leaves no journal entry at all, which is what
    /// makes "writes nothing" true of the save as well as of the inventories.
    @Test func aRefusedTransactionJournalsNothing() throws {
        let shop = try openShop(playerGold: 1)
        let before = shop.harness.store.nextJournalSequence
        #expect(throws: (any Error).self) {
            try shop.session.buy(Fixture.cuirass)
        }
        #expect(shop.harness.store.nextJournalSequence == before)
    }
}
