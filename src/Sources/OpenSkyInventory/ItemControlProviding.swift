// Main-app world-item inspection seam: take, drop, and container sessions,
// without the readout depending on `GameViewController`. One snapshot value, so the
// readout comes from one observation. AppKit-free.

import Foundation
public import OpenSkyInventoryInterface

/// One equipped item as the readout spells it.
nonisolated struct EquippedItemReadout: Equatable, Sendable {
    let name: String
    /// Biped slots and hands it occupies, preformatted — the readout has no
    /// business knowing how to render a `BodySlots` bitfield.
    let occupancy: String
    /// The item's enchantment and what it has left, preformatted, or nil when it has
    /// none or the session has no ENCH index.
    let enchantment: String?

    init(name: String, occupancy: String, enchantment: String? = nil) {
        self.name = name
        self.occupancy = occupancy
        self.enchantment = enchantment
    }
}

/// One observation of the world-item runtime.
nonisolated struct ItemControlSnapshot: Equatable, Sendable {
    /// The player's stacks, in the component's FormID order.
    let playerStacks: [ItemStackReadout]
    /// The open container's name, or nil when no session is live.
    let containerName: String?
    /// Human-readable result of the last control action.
    let lastActionText: String

    /// The reading with no runtime attached.
    static let unavailable = ItemControlSnapshot(
        playerStacks: [],
        containerName: nil,
        lastActionText: "World items unavailable: no game data loaded."
    )
}
