// The M12 gate seam (issue #180): what `World > Inventory & Equipment` reads
// and the one mutation it makes.
//
// The destination is the milestone's own verification surface, and it deals in
// the three things the rest of M12 left without one: putting an item into an
// inventory without a console command, saying who owns the reference under the
// crosshair, and saying what an actor is actually wearing and which pieces of
// it contributed no geometry. Taking, dropping, transferring, buying and
// selling already have surfaces — `World > HUD & Interaction > Items` and
// `World > Container Menu` — and are deliberately not duplicated here.
//
// One snapshot value rather than a bag of protocol properties, for the reason
// every other panel seam is one: the readout has to be a pure function of a
// single engine observation, not of several taken while the streamer mutates
// between them.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.
//
// Documented in docs/engine/inventory-equipment.md.

import Foundation

/// Which inventory a grant lands in.
///
/// Only two, and both are reachable without knowing a FormID: the player is
/// where the loop starts, and the open container is what a transfer and a
/// barter session both act on. A merchant is a container, so nominating one
/// under `World > Container Menu > Merchant` and opening it makes this the
/// merchant's stock too.
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

/// The `XOWN`/`XRNK` reading for one placed reference.
///
/// Ownership is decoded but not yet enforced — stealing is a crime system, and
/// no crime system exists — so this is an inspection, not a gate. It is on the
/// gate panel because "taking this is theft" is a fact the loop moves through
/// silently, and a milestone that cannot state it cannot claim to have decoded
/// it.
nonisolated struct ReferenceOwnershipReadout: Equatable, Sendable {
    /// How the reference is named in the world, matching the HUD prompt.
    let name: String
    let reference: FormID
    /// `XOWN` — the owning NPC_ or FACT, nil when the reference is unowned.
    let owner: FormID?
    /// `XRNK` — the faction rank required to use it freely. Meaningful only
    /// when `owner` is a FACT; nil when the field is absent.
    let factionRank: Int32?
    /// Whether taking or opening it would be theft, which is exactly "it has
    /// an owner". Stated as its own field so the readout does not re-derive
    /// the rule and the two can never disagree.
    var isOwned: Bool {
        owner != nil
    }
}

/// What one actor is wearing, and what its appearance resolution left out.
nonisolated struct EquipInspectReadout: Equatable, Sendable {
    /// The holder's display name, or nil when nothing resolves the selected
    /// target — no player inventory, or no resident actor.
    let name: String?
    /// The equipped set, with the slots and hands each piece occupies.
    let equipped: [EquippedItemReadout]
    /// `AppearanceSkip` lines for this actor from the last build of its cell,
    /// already stripped of the "ACHR <id>: " prefix. Always empty for the
    /// player, who has no rendered body until M14.
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
    /// scene. Every other field is then empty and the panel says so rather
    /// than showing a convincing zero.
    let isAvailable: Bool

    // MARK: Grants

    /// Whether a container session is open, so the panel can lock the
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
        lastActionText: "Inventory and equipment unavailable: no game data loaded."
    )
}

/// Live-renderer seam for the `World > Inventory & Equipment` panel.
///
/// `refocusGameView()` is deliberately absent: `HUDControlProviding` declares
/// it and the panel reaches it through the composed `WorldControlProviders`.
@MainActor
protocol InventoryEquipmentControlProviding: AnyObject {
    /// Which owner the equipment inspection reads. Settable because the
    /// selector is the section's only control and the snapshot has to reflect
    /// it on the next tick.
    var inventoryEquipmentInspectionTarget: EquipmentTargetSelector { get set }

    var inventoryEquipmentSnapshot: InventoryEquipmentSnapshot { get }

    /// Puts `count` of `item` into `target`'s inventory.
    ///
    /// A dev control with no analogue in the shipping game, which is the point:
    /// the gate's loop needs a known item in a known inventory before it can
    /// take, transfer, equip, buy, sell and drop it, and a synthetic starting
    /// state beats hunting the world for one. Nothing is validated against
    /// plausibility — granting a container a sword it would never stock is a
    /// legitimate thing to want — but an unknown form and a non-positive count
    /// are refused, because both would put a stack nothing can price or weigh
    /// into the accounting.
    ///
    /// - Returns: a human-readable outcome, including the reason for a refusal.
    @discardableResult
    func grantItem(_ item: FormID, count: Int32, to target: InventoryGrantTarget) -> String
}
