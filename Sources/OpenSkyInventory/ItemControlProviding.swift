// Main-app world-item inspection seam: take, drop, and container sessions,
// without the readout depending on `GameViewController`. One snapshot value, so the
// readout comes from one observation. AppKit-free.

import Foundation
import OpenSkyInventoryInterface

/// Who an equip or unequip applies to: the player for state and carry weight,
/// or the nearest actor to see the change on a rendered body.
nonisolated public enum EquipmentTargetSelector: Equatable, Sendable {
    case player
    /// The resident ACHR closest to the player.
    case nearestActor
}

/// One equipped item as the readout spells it.
nonisolated public struct EquippedItemReadout: Equatable, Sendable {
    public let name: String
    /// Biped slots and hands it occupies, preformatted — the readout has no
    /// business knowing how to render a `BodySlots` bitfield.
    public let occupancy: String
    /// The item's enchantment and what it has left, preformatted, or nil when it has
    /// none or the session has no ENCH index.
    public let enchantment: String?

    public init(name: String, occupancy: String, enchantment: String? = nil) {
        self.name = name
        self.occupancy = occupancy
        self.enchantment = enchantment
    }
}

/// One observation of the world-item runtime.
nonisolated public struct ItemControlSnapshot: Equatable, Sendable {
    /// The player's stacks, in the component's FormID order.
    public let playerStacks: [ItemStackReadout]
    /// The open container's name, or nil when no session is live.
    public let containerName: String?
    /// Human-readable result of the last control action.
    public let lastActionText: String

    /// Written out so the equipment members can trail the list with defaults.
    public init(
        playerStacks: [ItemStackReadout],
        containerName: String?,
        lastActionText: String
    ) {
        self.playerStacks = playerStacks
        self.containerName = containerName
        self.lastActionText = lastActionText
    }

    /// The reading with no runtime attached.
    public static let unavailable = ItemControlSnapshot(
        playerStacks: [],
        containerName: nil,
        lastActionText: "World items unavailable: no game data loaded."
    )
}
