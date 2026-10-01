// Faction vendors: finding the vendor faction, reading its chest, hours, and
// buy/sell list, and both list negations. Layouts: docs/formats/factions.md.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import Testing

struct VendorRulesTests {
    static let pluginName = "Vendors.esm"

    enum IDs {
        static let pawnbroker: UInt32 = 0x10
        static let fence: UInt32 = 0x11
        static let townsfolk: UInt32 = 0x12
        static let listless: UInt32 = 0x13
        static let miscList: UInt32 = 0x20
        static let nestedList: UInt32 = 0x21
        static let noSale: UInt32 = 0x30
        static let key: UInt32 = 0x31
        static let weapon: UInt32 = 0x32
        static let chest: UInt32 = 0x700
    }

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: pluginName.lowercased(), objectID: objectID)
    }

    private static func keyword(_ formID: UInt32, _ editorID: String) -> Data {
        ESMFixture.record(
            "KYWD", formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        )
    }

    private static func list(_ formID: UInt32, _ editorID: String, _ entries: [UInt32]) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        for entry in entries {
            fields += FactionFixture.link("LNAM", entry)
        }
        return ESMFixture.record("FLST", formID: formID, data: fields)
    }

    private static func vendorFaction(
        _ formID: UInt32,
        _ editorID: String,
        list: UInt32?,
        values: Data
    ) -> Data {
        var body = FactionFixture.flags(Faction.Flags.vendor.rawValue)
        if let list {
            body += FactionFixture.link("VEND", list)
        }
        body += FactionFixture.link("VENC", IDs.chest) + values
        return FactionFixture.record(formID: formID, editorID: editorID, body: body)
    }

    /// Belethor's shape and Tonilia's: the same negated two-keyword list, with
    /// the second a fence. The list nests one level so flattening is exercised.
    static func resolver() throws -> VendorResolver {
        var data = ESMFixture.tes4()
        data += ESMFixture.topGroup(
            "KYWD",
            contents: keyword(IDs.noSale, "VendorNoSale")
                + keyword(IDs.key, "VendorItemKey")
                + keyword(IDs.weapon, "VendorItemWeapon")
        )
        data += ESMFixture.topGroup(
            "FLST",
            contents:
            list(IDs.miscList, "VendorItemsMisc", [IDs.noSale, IDs.nestedList])
                + list(IDs.nestedList, "Nested", [IDs.key])
        )
        data += ESMFixture.topGroup("FACT", contents: [
            vendorFaction(
                IDs.pawnbroker, "PawnbrokerFaction", list: IDs.miscList,
                values: FactionFixture.vendorValues(startHour: 8, endHour: 20, notSellBuy: true)
            ),
            vendorFaction(
                IDs.fence, "FenceFaction", list: IDs.miscList,
                values: FactionFixture.vendorValues(
                    startHour: 0, endHour: 24, onlyBuysStolenItems: true, notSellBuy: true
                )
            ),
            vendorFaction(
                IDs.listless, "ListlessFaction", list: nil,
                values: FactionFixture.vendorValues()
            ),
            FactionFixture.record(formID: IDs.townsfolk, editorID: "TownsfolkFaction")
        ].reduce(Data(), +))
        let file = try ESMFile(data: data)
        let plugins = [(pluginName, file)]
        return VendorResolver(
            factions: FactionStore(plugins: plugins),
            formLists: FormListStore(plugins: plugins)
        )
    }

    static func memberships(_ factions: [UInt32]) -> ActorFactionState {
        ActorFactionState(memberships: factions.map {
            ActorFactionMembership(faction: key($0), rank: 0)
        })
    }

    // MARK: - Resolution

    @Test func theFirstVendorFactionAmongTheMembershipsWins() throws {
        let resolver = try Self.resolver()
        let vendor = try #require(resolver.vendor(
            memberships: Self.memberships([IDs.townsfolk, IDs.pawnbroker, IDs.fence])
        ))
        #expect(vendor.faction == Self.key(IDs.pawnbroker))
        #expect(vendor.merchantChest == Self.key(IDs.chest))
        #expect(vendor.hours == VendorHours(start: 8, end: 20))
        #expect(vendor.negatesList)
        #expect(!vendor.buysStolen)
        #expect(vendor.listKeywords == [Self.key(IDs.noSale), Self.key(IDs.key)])
        #expect(resolver.vendor(memberships: Self.memberships([IDs.townsfolk])) == nil)
    }

    @Test func theFenceFlagAndAMissingListResolve() throws {
        let resolver = try Self.resolver()
        let fence = try #require(resolver.vendor(memberships: Self.memberships([IDs.fence])))
        #expect(fence.buysStolen)
        let listless = try #require(
            resolver.vendor(memberships: Self.memberships([IDs.listless]))
        )
        #expect(listless.listKeywords == nil)
        #expect(listless.trades(keywords: [Self.key(IDs.noSale)]))
    }

    @Test func itemKeywordsResolveToTheListsIdentities() throws {
        let resolver = try Self.resolver()
        let keywords = resolver.keywords(
            [FormID(IDs.key), FormID(0x999)], fromPlugin: Self.pluginName
        )
        #expect(keywords.contains(Self.key(IDs.key)))
    }

    // MARK: - Gating

    @Test func theListGatesBothWaysOfItsNegation() throws {
        let resolver = try Self.resolver()
        let negated = try #require(
            resolver.vendor(memberships: Self.memberships([IDs.pawnbroker]))
        )
        #expect(!negated.trades(keywords: [Self.key(IDs.key)]))
        #expect(negated.trades(keywords: [Self.key(IDs.weapon)]))
        #expect(negated.trades(keywords: []))

        let plain = Vendor(
            faction: negated.faction,
            factionName: "Plain",
            merchantChest: nil,
            hours: nil,
            listKeywords: negated.listKeywords,
            negatesList: false,
            buysStolen: false
        )
        #expect(plain.trades(keywords: [Self.key(IDs.key)]))
        #expect(!plain.trades(keywords: [Self.key(IDs.weapon)]))
        #expect(!plain.trades(keywords: []))
    }

    @Test func hoursAreStartInclusiveEndExclusiveAndCanWrap() {
        let day = VendorHours(start: 8, end: 20)
        #expect(!day.isOpen(atHour: 7.99))
        #expect(day.isOpen(atHour: 8))
        #expect(day.isOpen(atHour: 19.5))
        #expect(!day.isOpen(atHour: 20))

        let always = VendorHours(start: 0, end: 24)
        #expect(always.isOpen(atHour: 0) && always.isOpen(atHour: 23.9))
        #expect(VendorHours(start: 0, end: 25).isOpen(atHour: 23.9))
        #expect(VendorHours(start: 0, end: 0).isOpen(atHour: 12))

        let night = VendorHours(start: 20, end: 4)
        #expect(night.isOpen(atHour: 22) && night.isOpen(atHour: 3))
        #expect(!night.isOpen(atHour: 12))
    }
}
