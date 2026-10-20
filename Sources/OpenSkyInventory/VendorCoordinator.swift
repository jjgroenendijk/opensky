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
    /// Where `actor` stands and the point `place` names. Nil when the actor is not
    /// streamed in.
    func vendorPlaceFacts(of actor: ReferenceKey, for place: VendorPlace) -> VendorPlaceFacts?
    /// The name of the first vendor condition that fails on `merchant`, or nil.
    func failingVendorCondition(
        _ conditions: ConditionList, sourcePlugin: String, merchant: ReferenceKey
    ) -> String?
    /// Game hours since the start, or nil without a game clock.
    var totalGameHours: Double? { get }
    var vendorRestockLedger: VendorRestockLedger { get set }
    /// Returns `chest` to its plugin stock and gold.
    func restockMerchantChest(_ chest: ReferenceKey)
}

/// Why the barter menu did not open.
nonisolated public enum BarterOpenRefusal: Error, Equatable, Sendable {
    case notAMerchant
    /// The chest's stock is a leveled list, so an unstreamed chest is refused
    /// rather than shown empty.
    case chestNotResident(factionName: String)
    /// The vendor is closed, away from its place, or fails a condition.
    case notTrading(factionName: String, VendorUnavailability)
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
    public var restockSettings = VendorRestockSettings.vanilla
    private weak var world: (any VendorWorld)?

    public init(core: VendorCore, world: any VendorWorld) {
        self.core = core
        self.world = world
    }

    /// `actor`'s vendor role, from its seeded memberships: the first vendor
    /// faction that trades now, else the first one.
    public func vendor(of actor: ReferenceKey) -> Vendor? {
        trading(actor)?.vendor
    }

    /// Why `vendor` does not trade with `actor` as the merchant now, or nil.
    public func unavailability(of vendor: Vendor, merchant actor: ReferenceKey)
        -> VendorUnavailability?
    {
        VendorCore.unavailability(
            of: vendor,
            hour: world?.hourOfDay,
            allowsPlace: vendor.location.map { rule in
                rule.allows(world?.vendorPlaceFacts(of: actor, for: rule.place))
            } ?? true,
            failingCondition: vendor.conditions.conditions.isEmpty ? nil
                : world?.failingVendorCondition(
                    vendor.conditions, sourcePlugin: vendor.sourcePlugin, merchant: actor
                )
        )
    }

    private func trading(_ actor: ReferenceKey) -> (
        vendor: Vendor, refusal: VendorUnavailability?
    )? {
        guard let memberships = world?.factionMemberships(of: actor) else { return nil }
        return VendorCore.trading(core.resolver.vendors(memberships: memberships)) {
            unavailability(of: $0, merchant: actor)
        }
    }

    /// Who `actor` trades as. `override` names a vendor faction to use in place
    /// of the one its memberships resolve.
    public func counterparty(
        for actor: ReferenceKey,
        vendorFaction override: ReferenceKey? = nil
    ) -> Result<BarterCounterparty, BarterOpenRefusal> {
        let vendor = override.flatMap(core.vendor(faction:)) ?? vendor(of: actor)
        if let vendor, let refusal = unavailability(of: vendor, merchant: actor) {
            return .failure(.notTrading(factionName: vendor.factionName, refusal))
        }
        if let chest = vendor?.merchantChest {
            restockIfDue(chest)
        }
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

    /// A chest first seen now counts as stocked now; one stocked a full interval ago
    /// returns to its plugin stock. Only a chest restocks: a vendor that sells from
    /// its own inventory keeps what the player sold it.
    public func restockIfDue(_ chest: ReferenceKey) {
        guard let world, let now = world.totalGameHours else { return }
        var ledger = world.vendorRestockLedger
        if let stocked = ledger.stockedAt[chest] {
            guard restockSettings.isDue(stockedAt: stocked, now: now) else { return }
            world.restockMerchantChest(chest)
        }
        ledger.stockedAt[chest] = now
        world.vendorRestockLedger = ledger
    }

    /// Moves every chest's last stocking back one interval, so each restocks on the
    /// next barter.
    @discardableResult
    public func makeAllRestocksDue() -> Int {
        guard let world else { return 0 }
        var ledger = world.vendorRestockLedger
        let wait = Double(max(0, restockSettings.days) * 24)
        for (chest, stocked) in ledger.stockedAt {
            ledger.stockedAt[chest] = stocked - wait
        }
        world.vendorRestockLedger = ledger
        return ledger.stockedAt.count
    }

    private func stock(at key: ReferenceKey) -> VendorStock? {
        guard let owner = world?.residentOwner(of: key) else { return nil }
        return VendorStock(owner: owner, cell: world?.cellLocation(of: key))
    }
}
