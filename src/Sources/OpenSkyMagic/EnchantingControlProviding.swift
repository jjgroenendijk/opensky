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

extension MagicCoordinator.EnchantingReadout {
    var enchantingSnapshot: EnchantingControlSnapshot {
        guard
            coordinator.effects != nil, coordinator.enchantmentStore != nil,
            let inventory = coordinator.world.inventory
        else {
            return .unavailable
        }
        return EnchantingControlSnapshot(
            gems: coordinator.soulTrapping.carriedGems(inventory).filter { $0.soul != .empty }.map {
                EnchantingGemReadout(gem: $0)
            }
        )
    }
}
