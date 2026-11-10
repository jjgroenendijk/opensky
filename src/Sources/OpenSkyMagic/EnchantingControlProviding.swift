// Enchanting: disenchant a carried item, and enchant a plain one
// with known bases and a filled soul gem, as if at an arcane enchanter.
// See docs/engine/enchanting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

/// One filled soul gem copy the player carries.
nonisolated struct EnchantingGemReadout: Equatable, Sendable {
    let gem: SoulGemCandidate
}

nonisolated struct EnchantingControlSnapshot: Equatable, Sendable {
    static let unavailable = EnchantingControlSnapshot(gems: []
    )

    let gems: [EnchantingGemReadout]
}

extension MagicCoordinator {
    var enchantingSnapshot: EnchantingControlSnapshot {
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
