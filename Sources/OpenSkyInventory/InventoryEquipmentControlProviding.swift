// The seam `World > Inventory & Equipment` reads: grant an item, show who owns the
// reference under the crosshair, and show what an actor wears. Taking, trading
// and dropping have their own panels. One snapshot value, so the readout comes
// from a single observation. See docs/engine/inventory-equipment.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

/// Which inventory a grant lands in: the player or the open container. A merchant
/// is a container, so an opened merchant receives the grant as stock.
nonisolated public enum InventoryGrantTarget: String, Equatable, Sendable, CaseIterable {
    case player
    case openContainer

    /// How the control and the readout name it.
    public var label: String {
        switch self {
        case .player: "Player"
        case .openContainer: "Open container"
        }
    }
}

/// What one actor is wearing, and what its appearance resolution left out.
nonisolated public struct EquipInspectReadout: Equatable, Sendable {
    /// The holder's display name, or nil when nothing resolves the selected
    /// target — no player inventory, or no resident actor.
    public let name: String?
    /// The equipped set, with the slots and hands each piece occupies.
    public let equipped: [EquippedItemReadout]
    /// `AppearanceSkip` lines for this actor from its cell's last build, without the
    /// "ACHR <id>: " prefix. Always empty for the player.
    public let appearanceSkips: [String]
    /// True when the actor's cell rendered it from its runtime equipped set
    /// rather than from the plugin default outfit. False for the player.
    public let usesRuntimeEquipment: Bool

    public static let unresolved = EquipInspectReadout(
        name: nil, equipped: [], appearanceSkips: [], usesRuntimeEquipment: false
    )

    public init(
        name: String?,
        equipped: [EquippedItemReadout],
        appearanceSkips: [String],
        usesRuntimeEquipment: Bool
    ) {
        self.name = name
        self.equipped = equipped
        self.appearanceSkips = appearanceSkips
        self.usesRuntimeEquipment = usesRuntimeEquipment
    }
}

/// One observation of everything the gate destination shows.
nonisolated public struct InventoryEquipmentSnapshot: Equatable, Sendable {
    /// False when no inventory runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather
    /// than showing a convincing zero.
    public let isAvailable: Bool

    // MARK: Grants

    /// Whether a container session is open, so the panel can lock the
    /// open-container grant target rather than offer a grant that would be
    /// refused.
    public let hasOpenContainer: Bool
    /// The open container's display name, nil when no session is live.
    public let openContainerName: String?
    /// Stacks the player holds, in the component's FormID order.
    public let playerStacks: [ItemStackReadout]
    public let playerGold: Int32
    public let playerWeight: Float
    /// Stacks the open container holds; empty when none is open.
    public let containerStacks: [ItemStackReadout]
    public let containerGold: Int32

    // MARK: Ownership

    /// The crosshair target's ownership, nil when the crosshair is on nothing.
    public let targetOwnership: ReferenceOwnershipReadout?

    // MARK: Equipment

    /// Which owner the equipment inspection is reading.
    public let equipTarget: EquipmentTargetSelector
    public let equipInspection: EquipInspectReadout
    /// What the session's resolved-enchantment cache holds and how often it was
    /// reused instead of re-walked from the records.
    public let enchantmentCache: EnchantmentCacheReadout

    /// Human-readable result of the last grant, shown verbatim.
    public let lastActionText: String

    /// The reading with no runtime attached.
    public static let unavailable = InventoryEquipmentSnapshot(
        isAvailable: false,
        hasOpenContainer: false,
        openContainerName: nil,
        playerStacks: [],
        playerGold: 0,
        playerWeight: 0,
        containerStacks: [],
        containerGold: 0,
        targetOwnership: nil,
        equipTarget: .nearestActor,
        equipInspection: .unresolved,
        enchantmentCache: .empty,
        lastActionText: "Inventory and equipment unavailable: no game data loaded."
    )

    public init(
        isAvailable: Bool,
        hasOpenContainer: Bool,
        openContainerName: String?,
        playerStacks: [ItemStackReadout],
        playerGold: Int32,
        playerWeight: Float,
        containerStacks: [ItemStackReadout],
        containerGold: Int32,
        targetOwnership: ReferenceOwnershipReadout?,
        equipTarget: EquipmentTargetSelector,
        equipInspection: EquipInspectReadout,
        enchantmentCache: EnchantmentCacheReadout,
        lastActionText: String
    ) {
        self.isAvailable = isAvailable
        self.hasOpenContainer = hasOpenContainer
        self.openContainerName = openContainerName
        self.playerStacks = playerStacks
        self.playerGold = playerGold
        self.playerWeight = playerWeight
        self.containerStacks = containerStacks
        self.containerGold = containerGold
        self.targetOwnership = targetOwnership
        self.equipTarget = equipTarget
        self.equipInspection = equipInspection
        self.enchantmentCache = enchantmentCache
        self.lastActionText = lastActionText
    }
}

/// Live-renderer seam for the `World > Inventory & Equipment` panel.
///
/// `refocusGameView()` is deliberately absent: `HUDControlProviding` declares
/// it and the panel reaches it through the composed `WorldControlProviders`.
@MainActor
public protocol InventoryEquipmentControlProviding: AnyObject {
    /// Which owner the equipment inspection reads. Settable because the
    /// selector is the section's only control and the snapshot has to reflect
    /// it on the next tick.
    var inventoryEquipmentInspectionTarget: EquipmentTargetSelector { get set }

    var inventoryEquipmentSnapshot: InventoryEquipmentSnapshot { get }

    /// Puts `count` of `item` into `target`'s inventory: a dev control. Plausibility
    /// is not checked, but an unknown form or a non-positive count is refused.
    /// - Returns: a readable outcome, with the reason for a refusal.
    @discardableResult
    func grantItem(_ item: FormID, count: Int32, to target: InventoryGrantTarget) -> String
}
