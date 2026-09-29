// A World > Crime & Factions reading with a bounty, a stolen stack, a guard
// subject and a vendor, shared by the readout suite and the panel suite.

@testable import OpenSkyCrime
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventoryInterface

public enum CrimeFactionSnapshotFixture {
    public static let hold = option(0x10, "Hold")
    public static let guild = option(0x20, "Guild")
    public static let shop = option(0x30, "Shop")

    public static func option(_ objectID: UInt32, _ name: String) -> FactionOption {
        FactionOption(key: .plugin(name: "base.esm", objectID: objectID), name: name)
    }

    /// A reading with a bounty, a stolen stack, a guard subject and a vendor.
    public static func snapshot(hour: Float = 12) -> CrimeFactionControlSnapshot {
        let vendor = Vendor(
            faction: shop.key, factionName: "Shop", merchantChest: nil,
            hours: VendorHours(start: 8, end: 20), listKeywords: [], negatesList: true,
            buysStolen: false
        )
        return CrimeFactionControlSnapshot(
            isAvailable: true,
            bounties: [BountyReadout(
                faction: hold, nonViolentGold: 40, violentGold: 1000,
                counts: CrimeCounts.none.incrementing(.murder),
                response: .attackOnSight(bounty: 1040)
            )],
            currentCrimeFaction: hold,
            ownership: nil,
            ownerName: nil,
            stolenStacks: [
                ItemStackReadout(item: FormID(0x42), count: 2, name: "Ring", stolen: true)
            ],
            crimeFactions: [hold],
            selectedCrimeFaction: hold.key,
            playerMemberships: [MembershipReadout(faction: guild, rank: 2)],
            subject: SocialSubjectReadout(
                key: .plugin(name: "base.esm", objectID: 0x900), name: "Guard",
                memberships: [MembershipReadout(faction: hold, rank: 0)],
                towardPlayer: nil, crimeFaction: hold, policedFaction: hold, vendor: vendor
            ),
            factions: [guild, hold, shop],
            selectedFaction: guild.key,
            vendorFactions: [shop],
            vendorOverride: nil,
            effectiveVendor: vendor,
            hour: hour,
            lastCrimeText: "Murder: 1000 bounty with Hold.",
            lastGuardText: "No guard has acted yet.",
            lastActionText: "No crime or faction action yet."
        )
    }
}
