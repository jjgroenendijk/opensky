// Enchanting: disenchant a carried item, and enchant a plain one
// with known bases and a filled soul gem, as if at an arcane enchanter.
// See docs/engine/enchanting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

/// One filled soul gem copy the player carries.
nonisolated public struct EnchantingGemReadout: Equatable, Sendable {
    public let gem: SoulGemCandidate

    public init(gem: SoulGemCandidate) {
        self.gem = gem
    }
}

nonisolated public struct EnchantingControlSnapshot: Equatable, Sendable {
    public static let unavailable = EnchantingControlSnapshot(gems: []
    )

    public let gems: [EnchantingGemReadout]

    public init(
        gems: [EnchantingGemReadout]
    ) {
        self.gems = gems
    }
}

extension MagicCoordinator {
    public var enchantingSnapshot: EnchantingControlSnapshot {
        guard effects != nil, enchantmentStore != nil, let inventory = world.inventory else {
            return .unavailable
        }
        return EnchantingControlSnapshot(
            gems: carriedGems(inventory).filter { $0.soul != .empty }.map {
                EnchantingGemReadout(gem: $0)
            }
        )
    }
}
