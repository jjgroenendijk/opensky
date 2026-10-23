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
    /// False when no inventory runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the readout says so rather than
    /// showing a convincing zero.
    public let isAvailable: Bool
    /// The crosshair target's name, when it has one.
    public let targetName: String?
    /// Whether activating the current target would take it.
    public let targetIsTakeable: Bool
    /// Whether activating the current target would open a container.
    public let targetIsContainer: Bool
    /// The player's stacks, in the component's FormID order.
    public let playerStacks: [ItemStackReadout]
    /// Total carried weight.
    public let playerWeight: Float
    /// Gold, which is an ordinary stack of the vanilla gold form.
    public let playerGold: Int32
    /// The open container's name, or nil when no session is live.
    public let containerName: String?
    /// The open container's contents, re-read every observation.
    public let containerStacks: [ItemStackReadout]
    /// Objects the running game has spawned and not yet taken back — dropped
    /// items, across every cell whether resident or not.
    public let spawnedObjectCount: Int
    /// What the player is wearing.
    public let playerEquipped: [EquippedItemReadout]
    /// How the nearest resident ACHR is named, or nil when none is loaded.
    public let nearestActorName: String?
    /// What that actor is wearing — the set an equip is actually visible on.
    public let nearestActorEquipped: [EquippedItemReadout]
    /// Human-readable result of the last control action.
    public let lastActionText: String
    /// The `CarryWeight` actor value. Above it the player can only walk.
    public let playerCapacity: Float?

    /// Written out so the equipment members can trail the list with defaults.
    public init(
        isAvailable: Bool,
        targetName: String?,
        targetIsTakeable: Bool,
        targetIsContainer: Bool,
        playerStacks: [ItemStackReadout],
        playerWeight: Float,
        playerGold: Int32,
        containerName: String?,
        containerStacks: [ItemStackReadout],
        spawnedObjectCount: Int,
        lastActionText: String,
        playerEquipped: [EquippedItemReadout] = [],
        nearestActorName: String? = nil,
        nearestActorEquipped: [EquippedItemReadout] = [],
        playerCapacity: Float? = nil
    ) {
        self.isAvailable = isAvailable
        self.targetName = targetName
        self.targetIsTakeable = targetIsTakeable
        self.targetIsContainer = targetIsContainer
        self.playerStacks = playerStacks
        self.playerWeight = playerWeight
        self.playerGold = playerGold
        self.containerName = containerName
        self.containerStacks = containerStacks
        self.spawnedObjectCount = spawnedObjectCount
        self.lastActionText = lastActionText
        self.playerEquipped = playerEquipped
        self.nearestActorName = nearestActorName
        self.nearestActorEquipped = nearestActorEquipped
        self.playerCapacity = playerCapacity
    }

    /// The reading with no runtime attached.
    public static let unavailable = ItemControlSnapshot(
        isAvailable: false,
        targetName: nil,
        targetIsTakeable: false,
        targetIsContainer: false,
        playerStacks: [],
        playerWeight: 0,
        playerGold: 0,
        containerName: nil,
        containerStacks: [],
        spawnedObjectCount: 0,
        lastActionText: "World items unavailable: no game data loaded."
    )
}
