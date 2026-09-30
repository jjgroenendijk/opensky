// The vendor shell over a fake world: it reads the memberships, the stock,
// the hour, and item keywords, and hands them to the core. The decisions are
// tested in `VendorCoreTests`.

import Foundation
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import Testing

@MainActor
struct VendorCoordinatorTests {
    private typealias IDs = VendorRulesTests.IDs

    private final class FakeWorld: VendorWorld {
        var memberships: [ReferenceKey: ActorFactionState] = [:]
        var owners: [ReferenceKey: InventoryOwner] = [:]
        var keywords: [FormID: [FormID]] = [:]
        var hourOfDay: Float?

        func factionMemberships(of actor: ReferenceKey) -> ActorFactionState? {
            memberships[actor]
        }

        func residentOwner(of key: ReferenceKey) -> InventoryOwner? {
            owners[key]
        }

        func cellLocation(of _: ReferenceKey) -> CellSceneLocation? {
            .interior(FormID(0x500))
        }

        func itemKeywords(of item: FormID) -> [FormID]? {
            keywords[item]
        }
    }

    private static let merchant = ReferenceKey.plugin(name: "vendors.esm", objectID: 0x900)
    private static let chest = VendorRulesTests.key(IDs.chest)

    private static func coordinator(_ world: FakeWorld) throws -> VendorCoordinator {
        try VendorCoordinator(
            core: VendorCore(
                resolver: VendorRulesTests.resolver(),
                itemPluginName: VendorRulesTests.pluginName
            ),
            world: world
        )
    }

    @Test func aResidentMerchantChestIsTheCounterparty() throws {
        let world = FakeWorld()
        world.memberships[Self.merchant] = VendorRulesTests.memberships([IDs.pawnbroker])
        world.owners[Self.chest] = .container(base: FormID(0x701))
        let found = try Self.coordinator(world).counterparty(for: Self.merchant).get()
        #expect(found.vendor.faction == VendorRulesTests.key(IDs.pawnbroker))
        #expect(found.holder == InventoryHolder(
            key: Self.chest,
            owner: .container(base: FormID(0x701)),
            cell: .interior(FormID(0x500))
        ))
    }

    @Test func theOverrideFactionReplacesTheMemberships() throws {
        let world = FakeWorld()
        world.owners[Self.chest] = .container(base: FormID(0x701))
        let found = try Self.coordinator(world).counterparty(
            for: Self.merchant,
            vendorFaction: VendorRulesTests.key(IDs.fence)
        ).get()
        #expect(found.vendor.buysStolen)
    }

    @Test func rulesReadTheHourAndTheItemKeywordsFromTheWorld() throws {
        let world = FakeWorld()
        let item = FormID(0x40)
        world.keywords[item] = [FormID(IDs.key)]
        world.hourOfDay = 12
        let coordinator = try Self.coordinator(world)
        let pawnbroker = try #require(
            coordinator.core.vendor(faction: VendorRulesTests.key(IDs.pawnbroker))
        )
        #expect(coordinator.rules(for: pawnbroker).refusal(for: item)
            == .vendorDoesNotTrade(item: item))
        #expect(coordinator.rules(for: pawnbroker).refusal(for: FormID(0x41)) == nil)
        world.hourOfDay = 21
        #expect(coordinator.rules(for: pawnbroker).refusal(for: FormID(0x41))
            == .vendorClosed(opens: 8, closes: 20))
        #expect(coordinator.rules(for: nil).refusal(for: item) == nil)
    }
}
