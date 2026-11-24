// A chest vendor's own inventory trades beside its chest, the player's bypass values
// open what a vendor buys, and no vendor buys a key.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkyWorldInterface
import Testing

@MainActor
struct BarterVendorStockTests {
    private typealias Items = InventoryBaselineFixture
    private typealias Parent = WorldItemRuntimeTests

    private static let faction = ReferenceKey.plugin(name: "vendors.esm", objectID: 0x10)
    private static let blockedKeyword = ReferenceKey.plugin(name: "vendors.esm", objectID: 0x31)
    private static let vendorSelf = InventoryHolder(
        key: .generated(77),
        owner: .generated,
        cell: nil
    )

    private static let vendor = Vendor(
        faction: faction,
        factionName: "Test Goods",
        merchantChest: nil,
        hours: nil,
        listKeywords: [blockedKeyword],
        negatesList: true,
        buysStolen: false
    )

    private struct Shop {
        let inventory: InventoryRuntime
        let chest: InventoryHolder
        let session: BarterSession
    }

    /// A chest with one cuirass and 10 gold, a vendor carrying one more cuirass and
    /// 1000 gold, and a player with gold, lockpicks, a key, and stolen swords.
    private func shop(bypass: VendorBypass = VendorBypass()) throws -> Shop {
        let harness = try Parent.standardHarness()
        let chest = try ContainerSession.open(Parent.interaction(
            reference: Parent.chestReference, base: Items.chest, action: .search
        ), in: harness.runtime).container
        let inventory = harness.runtime.inventory
        let chestCuirasses = inventory.count(of: Items.cuirass, in: chest)
        if chestCuirasses > 0 {
            try inventory.remove(Items.cuirass, count: chestCuirasses, from: chest)
        }
        try inventory.add(Items.cuirass, count: 1, to: chest)
        try inventory.add(inventory.goldFormID, count: 10, to: chest)
        try inventory.add(Items.cuirass, count: 1, to: Self.vendorSelf)
        try inventory.add(inventory.goldFormID, count: 1000, to: Self.vendorSelf)
        try inventory.add(inventory.goldFormID, count: 5000, to: .player)
        try inventory.add(Items.lockpick, count: 2, to: .player)
        try inventory.add(Items.key, count: 1, to: .player)
        try inventory.add(Items.sword, count: 2, to: .player, stolen: true)
        var rules = BarterRules(vendor: Self.vendor, hour: nil) { item in
            item == Items.lockpick ? [Self.blockedKeyword] : []
        }
        rules.bypass = bypass
        let session = BarterSession(
            runtime: harness.runtime, merchant: chest, pricing: .vanilla, rules: rules
        )
        session.ownStock = Self.vendorSelf
        return Shop(inventory: inventory, chest: chest, session: session)
    }

    @Test func theVendorsOwnStockAndGoldTradeBesideTheChest() throws {
        let shop = try shop()
        let chestGold = shop.inventory.goldCount(of: shop.chest)
        #expect(shop.session.merchantGold == chestGold + 1000)
        try shop.session.buy(Items.cuirass, count: 2)
        #expect(shop.inventory.count(of: Items.cuirass, in: shop.chest) == 0)
        #expect(shop.inventory.count(of: Items.cuirass, in: Self.vendorSelf) == 0)
        #expect(shop.inventory.count(of: Items.cuirass, in: .player) == 2)
    }

    @Test func aSaleTheChestCannotPayTakesTheVendorsOwnGold() throws {
        let shop = try shop(bypass: VendorBypass(stolen: true))
        let chestGold = shop.inventory.goldCount(of: shop.chest)
        let sale = try shop.session.sell(Items.sword, count: 2)
        #expect(sale.gold > 0)
        let total = shop.inventory.goldCount(of: shop.chest)
            + shop.inventory.goldCount(of: Self.vendorSelf)
        #expect(total == chestGold + 1000 - sale.gold)
    }

    @Test func theBypassValuesOpenTheListAndStolenGoods() throws {
        let plain = try shop()
        #expect(throws: BarterError.vendorDoesNotTrade(item: Items.lockpick)) {
            try plain.session.sell(Items.lockpick)
        }
        #expect(throws: BarterError.vendorRefusesStolen(item: Items.sword, stolen: 1)) {
            try plain.session.sell(Items.sword)
        }
        let merchant = try shop(bypass: VendorBypass(keywords: true))
        #expect(try merchant.session.sell(Items.lockpick).count == 1)
        // The keyword bypass opens only sales; buying still follows the list.
        #expect(merchant.session.rules.refusal(for: Items.lockpick) != nil)
        let fence = try shop(bypass: VendorBypass(stolen: true))
        #expect(try fence.session.sell(Items.sword).count == 1)
    }

    @Test func noVendorBuysAKey() throws {
        let shop = try shop(bypass: VendorBypass(keywords: true, stolen: true))
        #expect(throws: BarterError.vendorRefusesKey(item: Items.key)) {
            try shop.session.sell(Items.key)
        }
    }
}
