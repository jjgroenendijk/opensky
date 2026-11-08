import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

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

    public init(
        vendor: Vendor,
        holder: InventoryHolder
    ) {
        self.vendor = vendor
        self.holder = holder
    }
}
