// The pure vendor core: plain values in, counterparties and refusals out. No
// fake world. Records come from the synthetic plugin in `VendorRulesTests`.

import Foundation
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import Testing

struct VendorCoreTests {
    private typealias IDs = VendorRulesTests.IDs

    private static let merchant = ReferenceKey.plugin(name: "vendors.esm", objectID: 0x900)
    private static let chest = VendorRulesTests.key(IDs.chest)
    private static let chestStock = VendorStock(
        owner: .container(base: FormID(0x701)),
        cell: .interior(FormID(0x500))
    )

    private static func core() throws -> VendorCore {
        try VendorCore(
            resolver: VendorRulesTests.resolver(),
            itemPluginName: VendorRulesTests.pluginName
        )
    }

    private static func pawnbroker() throws -> Vendor {
        try #require(core().vendor(faction: VendorRulesTests.key(IDs.pawnbroker)))
    }

    private static func chestless(_ vendor: Vendor) -> Vendor {
        Vendor(
            faction: vendor.faction,
            factionName: vendor.factionName,
            merchantChest: nil,
            hours: vendor.hours,
            listKeywords: vendor.listKeywords,
            negatesList: vendor.negatesList,
            buysStolen: vendor.buysStolen
        )
    }

    @Test func membershipsWithNoVendorFactionResolveNoVendor() throws {
        let core = try Self.core()
        #expect(core.vendor(memberships: VendorRulesTests.memberships([IDs.townsfolk])) == nil)
        #expect(core.vendor(memberships: nil) == nil)
        #expect(core.vendor(faction: VendorRulesTests.key(IDs.townsfolk)) == nil)
    }

    @Test func noVendorIsNotAMerchant() {
        let result = VendorCore.counterparty(vendor: nil, actor: Self.merchant, stock: nil)
        #expect(result == .failure(.notAMerchant))
    }

    @Test func aChestVendorTradesFromItsResidentChest() throws {
        let vendor = try Self.pawnbroker()
        #expect(VendorCore.stockKey(of: vendor, actor: Self.merchant) == Self.chest)
        let found = try VendorCore.counterparty(
            vendor: vendor, actor: Self.merchant, stock: Self.chestStock
        ).get()
        #expect(found.vendor == vendor)
        #expect(found.holder == InventoryHolder(
            key: Self.chest,
            owner: Self.chestStock.owner,
            cell: Self.chestStock.cell
        ))
    }

    @Test func aChestThatIsNotStreamedInIsRefused() throws {
        let vendor = try Self.pawnbroker()
        let result = VendorCore.counterparty(vendor: vendor, actor: Self.merchant, stock: nil)
        #expect(result == .failure(.chestNotResident(factionName: vendor.factionName)))
    }

    @Test func aChestlessVendorTradesFromTheActorItself() throws {
        let vendor = try Self.chestless(Self.pawnbroker())
        #expect(VendorCore.stockKey(of: vendor, actor: Self.merchant) == Self.merchant)
        let actorStock = VendorStock(owner: .actor(base: FormID(0x901)), cell: nil)
        let found = try VendorCore.counterparty(
            vendor: vendor, actor: Self.merchant, stock: actorStock
        ).get()
        #expect(found.holder.key == Self.merchant)
    }

    @Test func stockOfTheWrongKindIsRefused() throws {
        let chestVendor = try Self.pawnbroker()
        let actorStock = VendorStock(owner: .actor(base: FormID(0x901)), cell: nil)
        #expect(VendorCore.counterparty(
            vendor: chestVendor, actor: Self.merchant, stock: actorStock
        ) == .failure(.chestNotResident(factionName: chestVendor.factionName)))
        #expect(VendorCore.counterparty(
            vendor: Self.chestless(chestVendor), actor: Self.merchant, stock: Self.chestStock
        ) == .failure(.chestNotResident(factionName: chestVendor.factionName)))
    }

    @Test func itemKeywordsNeedTheItemPlugin() throws {
        let core = try Self.core()
        #expect(core.keywords([FormID(IDs.key)]) == [VendorRulesTests.key(IDs.key)])
        #expect(core.keywords(nil).isEmpty)
        let pluginless = try VendorCore(resolver: VendorRulesTests.resolver(), itemPluginName: nil)
        #expect(pluginless.keywords([FormID(IDs.key)]).isEmpty)
    }
}
