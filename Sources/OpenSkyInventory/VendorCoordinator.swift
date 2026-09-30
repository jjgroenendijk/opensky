// Merchants for the barter menu: which vendor an actor or a faction is, which
// inventory it trades from, and the rules one trade runs under.
// See docs/engine/vendor-factions.md and docs/engine/coordinators.md.

import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// What `VendorCoordinator` reads from the running world.
public protocol VendorWorld: AnyObject {
    /// `actor`'s faction memberships, seeded from its record on first use.
    func factionMemberships(of actor: ReferenceKey) -> ActorFactionState?
    /// The owner a streamed-in reference stands for: `.actor` for an ACHR,
    /// `.container` for a REFR. Nil when `key` is not streamed in.
    func residentOwner(of key: ReferenceKey) -> InventoryOwner?
    func cellLocation(of key: ReferenceKey) -> CellSceneLocation?
    /// The item's `KWDA` keywords as the plugin wrote them.
    func itemKeywords(of item: FormID) -> [FormID]?
    /// Nil without a game clock, which leaves vendor hours ungated.
    var hourOfDay: Float? { get }
}

/// Why the barter menu did not open.
nonisolated public enum BarterOpenRefusal: Error, Equatable, Sendable {
    case notAMerchant
    /// The chest's stock is a leveled list, so an unstreamed chest is refused
    /// rather than shown empty.
    case chestNotResident(factionName: String)
}

/// The merchant side of one barter: the vendor and the inventory it sells from.
nonisolated public struct BarterCounterparty: Equatable, Sendable {
    public let vendor: Vendor
    public let holder: InventoryHolder
}

/// The vendor domain: resolves merchants and the rules they trade under.
public final class VendorCoordinator {
    public let resolver: VendorResolver
    /// The plugin that item keyword FormIDs are resolved from.
    private let itemPluginName: String?
    private weak var world: (any VendorWorld)?

    public init(resolver: VendorResolver, itemPluginName: String?, world: any VendorWorld) {
        self.resolver = resolver
        self.itemPluginName = itemPluginName
        self.world = world
    }

    /// `actor`'s vendor role, from its seeded memberships.
    public func vendor(of actor: ReferenceKey) -> Vendor? {
        guard let memberships = world?.factionMemberships(of: actor) else { return nil }
        return resolver.vendor(memberships: memberships)
    }

    /// Nil when `key` is not a vendor faction in this load order.
    public func vendor(faction key: ReferenceKey) -> Vendor? {
        guard let resolved = resolver.factions.faction(key: key), resolved.faction.isVendor else {
            return nil
        }
        return resolver.vendor(faction: resolved)
    }

    /// Who `actor` trades as. `override` names a vendor faction to use in place
    /// of the one its memberships resolve.
    ///
    /// The counterparty is the faction's merchant chest when it names one, and
    /// the actor's own inventory otherwise (UESP, Skyrim:Merchants).
    public func counterparty(
        for actor: ReferenceKey,
        vendorFaction override: ReferenceKey? = nil
    ) -> Result<BarterCounterparty, BarterOpenRefusal> {
        guard let vendor = override.flatMap(vendor(faction:)) ?? vendor(of: actor) else {
            return .failure(.notAMerchant)
        }
        guard let holder = holder(of: vendor, actor: actor) else {
            return .failure(.chestNotResident(factionName: vendor.factionName))
        }
        return .success(BarterCounterparty(vendor: vendor, holder: holder))
    }

    /// The rules a trade with `vendor` runs under. A nil vendor is a nominated
    /// container, which trades anything.
    public func rules(for vendor: Vendor?) -> BarterRules {
        guard let vendor else { return .unrestricted }
        let resolver = resolver
        let plugin = itemPluginName
        return BarterRules(vendor: vendor, hour: world?.hourOfDay) { [weak world] item in
            guard let plugin, let raw = world?.itemKeywords(of: item) else { return [] }
            return resolver.keywords(raw, fromPlugin: plugin)
        }
    }

    private func holder(of vendor: Vendor, actor: ReferenceKey) -> InventoryHolder? {
        let key = vendor.merchantChest ?? actor
        guard let owner = world?.residentOwner(of: key) else { return nil }
        switch (vendor.merchantChest, owner) {
        case (nil, .actor), (_?, .container):
            return InventoryHolder(key: key, owner: owner, cell: world?.cellLocation(of: key))
        default:
            return nil
        }
    }
}
