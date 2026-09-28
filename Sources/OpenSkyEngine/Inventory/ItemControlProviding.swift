// Main-app world-item inspection seam (issue #177, roadmap item 12.1.3). The
// provider keeps the panel independent of `GameViewController` while exposing
// the engine-owned take, drop and container-session operations.
//
// One snapshot value rather than a bag of protocol properties, for the same
// reason `RuntimeStateSnapshot` is one: the readout has to be a pure function
// of a single engine observation, not of several taken microseconds apart while
// the streamer is mutating between them.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.

import Foundation
import OpenSkyFormats

/// One stack as the panel spells it: what it is, how many, and what to call it.
nonisolated public struct ItemStackReadout: Equatable, Sendable {
    public let item: FormID
    public let count: Int32
    /// FULL name when the item index resolves one, else the editor ID, else the
    /// FormID. Never empty, so a readout line always names something.
    public let name: String
    /// Whether these copies were taken from somebody who owned them (issue
    /// #504). One row per stack, and a stack is keyed by (form, stolen), so an
    /// owner holding honest and stolen copies of one form shows two rows — the
    /// marker is what tells them apart.
    public let stolen: Bool

    public init(item: FormID, count: Int32, name: String, stolen: Bool = false) {
        self.item = item
        self.count = count
        self.name = name
        self.stolen = stolen
    }
}

/// Who an equip or unequip applies to (issue #178).
///
/// Two selectors, for the two things a session actually wants to do. The
/// player is where state and carry-weight accounting are checked; the nearest
/// actor is where the *visual* is checked, because the player has no rendered
/// body until M14 and an NPC is the only thing an equip can be seen on.
nonisolated public enum EquipmentTargetSelector: Equatable, Sendable {
    case player
    /// The resident ACHR closest to the player.
    case nearestActor
}

/// One equipped item as the panel spells it.
nonisolated public struct EquippedItemReadout: Equatable, Sendable {
    public let item: FormID
    public let name: String
    /// Biped slots and hands it occupies, preformatted — the panel has no
    /// business knowing how to render a `BodySlots` bitfield.
    public let occupancy: String
    /// The item's enchantment and what it has left, preformatted, or nil when it
    /// carries none and when the session has no ENCH index (issue #472). The
    /// panel has no business knowing the charge model either.
    public let enchantment: String?

    public init(item: FormID, name: String, occupancy: String, enchantment: String? = nil) {
        self.item = item
        self.name = name
        self.occupancy = occupancy
        self.enchantment = enchantment
    }
}

/// One observation of the world-item runtime.
nonisolated public struct ItemControlSnapshot: Equatable, Sendable {
    /// False when no inventory runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather than
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
    /// Total carried weight from #175's per-item weights.
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
    /// What the player is wearing (issue #178). State only: the player has no
    /// rendered body this milestone.
    public let playerEquipped: [EquippedItemReadout]
    /// How the nearest resident ACHR is named, or nil when none is loaded.
    public let nearestActorName: String?
    /// What that actor is wearing — the set an equip is actually visible on.
    public let nearestActorEquipped: [EquippedItemReadout]
    /// Human-readable result of the last panel action.
    public let lastActionText: String

    /// Written out rather than left to the memberwise initializer so the
    /// equipment members can trail the list with defaults, keeping the M12.1.3
    /// call sites compiling unchanged.
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
        nearestActorEquipped: [EquippedItemReadout] = []
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

@MainActor
public protocol ItemControlProviding: AnyObject {
    var itemControlSnapshot: ItemControlSnapshot { get }

    /// Takes the crosshair target into the player's inventory.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func takeInteractionTarget() -> String

    /// Opens a container session on the crosshair target, replacing any
    /// session already open.
    @discardableResult
    func openInteractionTargetContainer() -> String

    /// Moves everything in the open container to the player.
    @discardableResult
    func takeAllFromOpenContainer() -> String

    /// Ends the open container session.
    @discardableResult
    func closeOpenContainer() -> String

    /// Drops `count` of `item` in front of the player. A nil `item` drops from
    /// the player's first stack, which is what makes the control usable without
    /// knowing a FormID.
    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> String

    /// Equips `item` on `target`, unequipping whatever it conflicts with
    /// (issue #178). A nil `item` equips the target's first *equippable*
    /// unequipped stack, so the control works without knowing a FormID.
    ///
    /// - Returns: a human-readable outcome naming what was displaced.
    @discardableResult
    func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String

    /// Unequips `item` on `target`. A nil `item` unequips the first thing the
    /// target is wearing.
    @discardableResult
    func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String
}
