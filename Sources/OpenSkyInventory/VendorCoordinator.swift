// The world side of the vendor domain: the `VendorWorld` port and the shell
// that reads it for `VendorCore`.
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

/// The shell of the vendor domain: reads the world through `VendorWorld` and
/// hands the facts to `VendorCore`, which decides.
public final class VendorCoordinator {
    public let core: VendorCore
    private weak var world: (any VendorWorld)?

    public init(core: VendorCore, world: any VendorWorld) {
        self.core = core
        self.world = world
    }

    /// `actor`'s vendor role, from its seeded memberships.
    public func vendor(of actor: ReferenceKey) -> Vendor? {
        core.vendor(memberships: world?.factionMemberships(of: actor))
    }

    /// Who `actor` trades as. `override` names a vendor faction to use in place
    /// of the one its memberships resolve.
    public func counterparty(
        for actor: ReferenceKey,
        vendorFaction override: ReferenceKey? = nil
    ) -> Result<BarterCounterparty, BarterOpenRefusal> {
        let vendor = override.flatMap(core.vendor(faction:)) ?? vendor(of: actor)
        let vendorStock = vendor.flatMap { stock(at: VendorCore.stockKey(of: $0, actor: actor)) }
        return VendorCore.counterparty(vendor: vendor, actor: actor, stock: vendorStock)
    }

    /// The rules a trade with `vendor` runs under. A nil vendor is a nominated
    /// container, which trades anything.
    public func rules(for vendor: Vendor?) -> BarterRules {
        guard let vendor else { return .unrestricted }
        let core = core
        return BarterRules(vendor: vendor, hour: world?.hourOfDay) { [weak world] item in
            core.keywords(world?.itemKeywords(of: item))
        }
    }

    private func stock(at key: ReferenceKey) -> VendorStock? {
        guard let owner = world?.residentOwner(of: key) else { return nil }
        return VendorStock(owner: owner, cell: world?.cellLocation(of: key))
    }
}
