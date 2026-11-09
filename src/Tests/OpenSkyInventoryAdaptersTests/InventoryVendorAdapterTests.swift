// The vendor part reads a merchant's place, owner, and restock state from the session.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryAdapters
import OpenSkyInventoryInterface
import OpenSkySessionTesting
import OpenSkyWorldState
import Testing

@MainActor
struct InventoryVendorAdapterTests {
    private let host = InventoryHost()
    private var adapter: InventoryWorldAdapter {
        InventoryWorldAdapter(game: host)
    }

    private static let key = InventoryAdapterFixture.key
    private static let base = FormID(InventoryAdapterFixture.baseID)

    @Test func theOwnerFollowsThePlacedRecord() throws {
        #expect(adapter.residentOwner(of: Self.key) == nil)
        host.fakeStreamer.referenceEntryKeyResult = try InventoryAdapterFixture.actorEntry()
        #expect(adapter.residentOwner(of: Self.key) == .actor(base: Self.base))
        host.fakeStreamer.referenceEntryKeyResult = try InventoryAdapterFixture.referenceEntry()
        #expect(adapter.residentOwner(of: Self.key) == .container(base: Self.base))
    }

    @Test func membershipsAndCellsComeFromTheirPorts() {
        host.fakeStreamer.cellLocationResult = .interior(FormID(0x40))
        #expect(adapter.factionMemberships(of: Self.key) == nil)
        #expect(adapter.cellLocation(of: Self.key) == .interior(FormID(0x40)))
        #expect(host.fakeFactions.membershipsCalls == [Self.key])
    }

    @Test func aMerchantStandsWhereThePluginPlacedIt() throws {
        #expect(adapter.vendorPlaceFacts(of: Self.key, for: .nearSelf) == nil)
        host.fakeStreamer.referenceEntryKeyResult = try InventoryAdapterFixture.actorEntry()
        host.fakeStreamer.cellLocationResult = .interior(FormID(0x40))
        let near = try #require(adapter.vendorPlaceFacts(of: Self.key, for: .nearEditorLocation))
        #expect(near.position == .zero)
        #expect(near.target == .zero)
        #expect(near.cell == nil)
        let reference = adapter.vendorPlaceFacts(of: Self.key, for: .nearReference(Self.key))
        #expect(reference?.target == .zero)
        let linked = adapter.vendorPlaceFacts(of: Self.key, for: .linkedReference(keyword: nil))
        #expect(linked?.target == nil)
        let other = adapter.vendorPlaceFacts(of: Self.key, for: .nearPackageStart)
        #expect(other?.target == nil)
    }

    @Test func aMovedMerchantStandsWhereItMoved() throws {
        let moved = ReferenceTransformOverride(position: SIMD3(5, 6, 7), rotation: .zero)
        host.fakeStreamer.referenceEntryKeyResult = try InventoryAdapterFixture.actorEntry()
        host.fakeStreamer.npcTransformResult = moved
        let facts = adapter.vendorPlaceFacts(of: Self.key, for: .nearSelf)
        #expect(facts?.position == SIMD3(5, 6, 7))
    }

    @Test func theRestockLedgerIsKeptOnThePlayer() {
        #expect(adapter.vendorRestockLedger == VendorRestockLedger())
        adapter.vendorRestockLedger = VendorRestockLedger()
        #expect(host.fakeWorldState.setCalls.map(\.key) == [.player])
        adapter.restockMerchantChest(Self.key)
        #expect(host.fakeWorldState.resetKindForCalls.map(\.kind) == [.inventory, .itemCopies])
    }
}
