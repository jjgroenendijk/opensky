// Inventory and equipment controls: grant an item, show who owns the
// reference under the crosshair, and show what an actor wears. Taking, trading
// and dropping have their own readouts. One snapshot value, so the readout comes
// from a single observation. See docs/engine/inventory-equipment.md.

import Foundation
public import OpenSkyCrimeInterface
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface

/// Which inventory a grant lands in: the player or the open container. A merchant
/// is a container, so an opened merchant receives the grant as stock.
nonisolated enum InventoryGrantTarget: String, Equatable, Sendable, CaseIterable {
    case player
    case openContainer

    /// How the control and the readout name it.
    var label: String {
        switch self {
        case .player: "Player"
        case .openContainer: "Open container"
        }
    }
}

/// What one actor is wearing, and what its appearance resolution left out.
nonisolated struct EquipInspectReadout: Equatable, Sendable {
    /// The holder's display name, or nil when nothing resolves the selected
    /// target — no player inventory, or no resident actor.
    let name: String?
    /// The equipped set, with the slots and hands each piece occupies.
    let equipped: [EquippedItemReadout]
    /// `AppearanceSkip` lines for this actor from its cell's last build, without the
    /// "ACHR <id>: " prefix. Always empty for the player.
    let appearanceSkips: [String]
    /// True when the actor's cell rendered it from its runtime equipped set
    /// rather than from the plugin default outfit. False for the player.
    let usesRuntimeEquipment: Bool

    static let unresolved = EquipInspectReadout(
        name: nil, equipped: [], appearanceSkips: [], usesRuntimeEquipment: false
    )
}

/// One observation of everything the gate destination shows.
nonisolated struct InventoryEquipmentSnapshot: Equatable, Sendable {
    /// False when no inventory runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the readout says so rather
    /// than showing a convincing zero.
    let isAvailable: Bool

    // MARK: Grants

    /// Whether a container session is open, so the readout can lock the
    /// open-container grant target rather than offer a grant that would be
    /// refused.
    let hasOpenContainer: Bool
    /// The open container's display name, nil when no session is live.
    let openContainerName: String?
    /// Stacks the player holds, in the component's FormID order.
    let playerStacks: [ItemStackReadout]
    let playerGold: Int32
    let playerWeight: Float
    /// Stacks the open container holds; empty when none is open.
    let containerStacks: [ItemStackReadout]
    let containerGold: Int32

    // MARK: Ownership

    /// The crosshair target's ownership, nil when the crosshair is on nothing.
    let targetOwnership: ReferenceOwnershipReadout?

    // MARK: Equipment

    /// Which owner the equipment inspection is reading.
    let equipTarget: EquipmentTargetSelector
    let equipInspection: EquipInspectReadout
    /// What the session's resolved-enchantment cache holds and how often it was
    /// reused instead of re-walked from the records.
    let enchantmentCache: EnchantmentCacheReadout

    /// Human-readable result of the last grant, shown verbatim.
    let lastActionText: String

    /// The reading with no runtime attached.
    static let unavailable = InventoryEquipmentSnapshot(
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
}
