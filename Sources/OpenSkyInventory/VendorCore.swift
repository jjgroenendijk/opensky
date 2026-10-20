// The vendor decisions as pure functions: plugin data and world facts in,
// vendors and counterparties out. `VendorCoordinator` is the shell that reads
// the world. See docs/engine/coordinators.md.

import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// A streamed-in reference that can hold a vendor's stock.
nonisolated public struct VendorStock: Equatable, Sendable {
    public let owner: InventoryOwner
    public let cell: CellSceneLocation?

    public init(owner: InventoryOwner, cell: CellSceneLocation?) {
        self.owner = owner
        self.cell = cell
    }
}

/// Why a vendor is not trading right now.
nonisolated public enum VendorUnavailability: Equatable, Sendable {
    /// Outside the `VENV` hours, or a faction with no hours at all.
    case closed(VendorHours?)
    /// The merchant is not where its `PLVD` rule says it trades.
    case awayFromPlace
    /// A vendor condition failed; the function's name.
    case conditionFailed(String)

    public var text: String {
        switch self {
        case let .closed(hours?) where hours.start != hours.end:
            "closed, open \(hours.start) to \(hours.end)"
        case .closed: "offers no services: no trading hours"
        case .awayFromPlace: "not at the place it trades"
        case let .conditionFailed(function): "vendor condition \(function) fails"
        }
    }
}

/// The vendor rules over loaded plugin data. It reads no world state.
nonisolated public struct VendorCore: Sendable {
    public let resolver: VendorResolver
    /// The plugin that item keyword FormIDs are resolved from.
    public let itemPluginName: String?

    public init(resolver: VendorResolver, itemPluginName: String?) {
        self.resolver = resolver
        self.itemPluginName = itemPluginName
    }

    /// Nil for no memberships, which is an actor that is not streamed in.
    public func vendor(memberships: ActorFactionState?) -> Vendor? {
        memberships.flatMap(resolver.vendor(memberships:))
    }

    /// Nil when `key` is not a vendor faction in this load order.
    public func vendor(faction key: ReferenceKey) -> Vendor? {
        guard let resolved = resolver.factions.faction(key: key), resolved.faction.isVendor else {
            return nil
        }
        return resolver.vendor(faction: resolved)
    }

    /// Why `vendor` does not trade now, or nil when it does. A nil `hour` (no clock)
    /// leaves the hours ungated; `allowsPlace` and `failingCondition` come from the world.
    public static func unavailability(
        of vendor: Vendor,
        hour: Float?,
        allowsPlace: Bool,
        failingCondition: String?
    ) -> VendorUnavailability? {
        if let hour, !vendor.isOpen(atHour: hour) {
            return .closed(vendor.hours)
        }
        if !allowsPlace {
            return .awayFromPlace
        }
        return failingCondition.map(VendorUnavailability.conditionFailed)
    }

    /// The first vendor that trades now, else the first one with why it does not.
    public static func trading(
        _ vendors: [Vendor],
        unavailability: (Vendor) -> VendorUnavailability?
    ) -> (vendor: Vendor, refusal: VendorUnavailability?)? {
        var first: (Vendor, VendorUnavailability?)?
        for vendor in vendors {
            let refusal = unavailability(vendor)
            if refusal == nil {
                return (vendor, nil)
            }
            first = first ?? (vendor, refusal)
        }
        return first
    }

    /// The faction's merchant chest when it names one, and the actor's own
    /// inventory otherwise (UESP, Skyrim:Merchants).
    public static func stockKey(of vendor: Vendor, actor: ReferenceKey) -> ReferenceKey {
        vendor.merchantChest ?? actor
    }

    /// `stock` is what the world holds at `stockKey(of:actor:)`, or nil when
    /// nothing there is streamed in.
    public static func counterparty(
        vendor: Vendor?,
        actor: ReferenceKey,
        stock: VendorStock?
    ) -> Result<BarterCounterparty, BarterOpenRefusal> {
        guard let vendor else { return .failure(.notAMerchant) }
        guard let stock, holdsStock(stock.owner, for: vendor) else {
            return .failure(.chestNotResident(factionName: vendor.factionName))
        }
        let key = stockKey(of: vendor, actor: actor)
        let holder = InventoryHolder(key: key, owner: stock.owner, cell: stock.cell)
        return .success(BarterCounterparty(vendor: vendor, holder: holder))
    }

    /// A chest vendor sells from a container, and a chestless one from itself.
    private static func holdsStock(_ owner: InventoryOwner, for vendor: Vendor) -> Bool {
        switch (vendor.merchantChest, owner) {
        case (nil, .actor), (_?, .container): true
        default: false
        }
    }

    /// An item's raw `KWDA` keywords as the identities a vendor list holds.
    public func keywords(_ raw: [FormID]?) -> Set<ReferenceKey> {
        guard let itemPluginName, let raw else { return [] }
        return resolver.keywords(raw, fromPlugin: itemPluginName)
    }
}
