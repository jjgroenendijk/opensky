// Vendor rules on a live barter session (issue #506): hours and the buy/sell
// list refuse a trade and write nothing, a vendor that is not a fence refuses
// stolen copies, and a fence and a vendor purchase both launder the goods.
// Reuses `WorldItemRuntimeTests`' reference harness, so the merchant is an
// ordinary container reference.

import Foundation
@testable import OpenSky
@testable import OpenSkyFormats
import Testing

@MainActor
struct BarterVendorRulesTests {
    private typealias Items = InventoryBaselineFixture
    private typealias Parent = WorldItemRuntimeTests

    private static let faction = ReferenceKey.plugin(name: "vendors.esm", objectID: 0x10)
    private static let blockedKeyword = ReferenceKey.plugin(name: "vendors.esm", objectID: 0x31)

    private static func vendor(
        hours: VendorHours? = VendorHours(start: 8, end: 20),
        buysStolen: Bool = false
    ) -> Vendor {
        Vendor(
            faction: faction,
            factionName: "Test Goods",
            merchantChest: nil,
            hours: hours,
            listKeywords: [blockedKeyword],
            negatesList: true,
            buysStolen: buysStolen
        )
    }

    private struct Shop {
        let inventory: InventoryRuntime
        let merchant: InventoryHolder
        let session: BarterSession
    }

    /// A merchant with a purse and two cuirasses, facing a player with gold, two
    /// stolen swords and a sword that is theirs. Lockpicks carry the blocked
    /// keyword.
    private func shop(vendor: Vendor?, hour: Float? = 12) throws -> Shop {
        let harness = try Parent.standardHarness()
        let merchant = try harness.runtime.openContainer(Parent.interaction(
            reference: Parent.chestReference, base: Items.chest, action: .search
        )).container
        let inventory = harness.runtime.inventory
        try inventory.add(Items.cuirass, count: 2, to: merchant, stolen: true)
        try inventory.add(inventory.goldFormID, count: 5000, to: merchant)
        try inventory.add(inventory.goldFormID, count: 5000, to: .player)
        try inventory.add(Items.sword, count: 1, to: .player)
        try inventory.add(Items.sword, count: 2, to: .player, stolen: true)
        let rules = BarterRules(vendor: vendor, hour: hour) { item in
            item == Items.lockpick ? [Self.blockedKeyword] : []
        }
        let session = BarterSession(
            runtime: harness.runtime, merchant: merchant, pricing: .vanilla, rules: rules
        )
        return Shop(inventory: inventory, merchant: merchant, session: session)
    }

    @Test func aClosedVendorRefusesBothWaysAndWritesNothing() throws {
        let shop = try shop(vendor: Self.vendor(), hour: 21)
        let before = shop.inventory.inventory(of: .player)
        #expect(throws: BarterError.vendorClosed(opens: 8, closes: 20)) {
            try shop.session.buy(Items.cuirass)
        }
        #expect(throws: BarterError.vendorClosed(opens: 8, closes: 20)) {
            try shop.session.sell(Items.sword)
        }
        #expect(shop.inventory.inventory(of: .player) == before)
    }

    @Test func theListRefusesWhatItExcludes() throws {
        let shop = try shop(vendor: Self.vendor())
        #expect(throws: BarterError.vendorDoesNotTrade(item: Items.lockpick)) {
            try shop.session.buy(Items.lockpick)
        }
        #expect(try shop.session.buy(Items.cuirass).count == 1)
    }

    @Test func onlyAFenceTakesStolenCopiesAndItLaundersThem() throws {
        let honest = try shop(vendor: Self.vendor())
        // The first sword is the player's own, so it sells; the next reaches
        // the stolen copies and is refused.
        #expect(try honest.session.sell(Items.sword).count == 1)
        #expect(throws: BarterError.vendorRefusesStolen(item: Items.sword, stolen: 1)) {
            try honest.session.sell(Items.sword)
        }

        let fence = try shop(vendor: Self.vendor(hours: nil, buysStolen: true))
        try fence.session.sell(Items.sword, count: 3)
        #expect(fence.inventory.count(of: Items.sword, in: fence.merchant) == 3)
        #expect(fence.inventory.stolenCount(of: Items.sword, in: fence.merchant) == 0)
    }

    @Test func buyingFromAVendorLaundersButANominatedChestDoesNot() throws {
        // Three cuirasses: the chest's own honest one and the two stolen ones.
        let vendor = try shop(vendor: Self.vendor())
        try vendor.session.buy(Items.cuirass, count: 3)
        #expect(vendor.inventory.stolenCount(of: Items.cuirass, in: .player) == 0)

        let nominated = try shop(vendor: nil, hour: nil)
        try nominated.session.buy(Items.cuirass, count: 3)
        #expect(nominated.inventory.stolenCount(of: Items.cuirass, in: .player) == 2)
        // And with no vendor nothing is gated: stolen goods sell as before.
        #expect(try nominated.session.sell(Items.sword, count: 3).count == 3)
    }
}
