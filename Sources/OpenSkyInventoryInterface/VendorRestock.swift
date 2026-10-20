// When each merchant chest was last stocked, so its stock and gold return after
// `iDaysToRespawnVendor` days. UESP "Skyrim:Merchants": "Gold is reset ... every 48
// hours". See docs/engine/vendor-factions.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// Kept on the player: the game hour each merchant chest was last stocked.
nonisolated public struct VendorRestockLedger: WorldStateComponent, Hashable, Sendable {
    /// `GameClock.totalGameSeconds` / 3600 at the last stocking.
    public var stockedAt: [ReferenceKey: Double]

    public static var componentKind: WorldStateComponentKind {
        .vendorRestock
    }

    public init(stockedAt: [ReferenceKey: Double] = [:]) {
        self.stockedAt = stockedAt
    }
}

nonisolated extension WorldStateComponentKind {
    public static let vendorRestock = Self(
        rawValue: "vendorRestock", order: 41, affectsCellBuild: false
    )
}

/// `iDaysToRespawnVendor`, in game days.
nonisolated public struct VendorRestockSettings: Equatable, Sendable {
    /// `Skyrim.esm` sets 2.
    public var days = 2

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("iDaysToRespawnVendor", into: &settings, \.days)
        return settings
    }

    /// A chest restocks once a full interval has passed since it was last stocked.
    public func isDue(stockedAt stocked: Double, now: Double) -> Bool {
        guard stocked.isFinite, now.isFinite else { return false }
        return now - stocked >= Double(max(0, days) * 24)
    }
}
