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
import OpenSkyFormats

/// Which inventory a grant lands in.
///
/// Only two, and both are reachable without knowing a FormID: the player is
/// where the loop starts, and the open container is what a transfer and a
/// barter session both act on. A merchant is a container, so nominating one
/// under `World > Container Menu > Merchant` and opening it makes this the
/// merchant's stock too.
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

/// The `XOWN`/`XRNK` reading for one placed reference, and what the crime
/// runtime makes of it.
///
/// It was an inspection until issue #504; since then ownership is enforced and
/// this states the enforced answer rather than the raw fields alone. It is on
/// the gate panel because "taking this is theft" is a fact the loop otherwise
/// moves through silently.
nonisolated public struct ReferenceOwnershipReadout: Equatable, Sendable {
    /// How the reference is named in the world, matching the HUD prompt.
    public let name: String
    public let reference: FormID
    /// `XOWN` — the owning NPC_ or FACT, nil when the reference itself is
    /// unowned. A reference with none may still be owned through its cell,
    /// which `isTheft` accounts for and this field does not.
    public let owner: FormID?
    /// `XRNK` — the faction rank required to use it freely. Meaningful only
    /// when `owner` is a FACT; nil when the field is absent.
    public let factionRank: Int32?
    /// Whether taking it would actually be theft for the player right now
    /// (issue #504): the `OwnershipVerdict` over the reference's own `XOWN`,
    /// the cell's, and the player's memberships. Not the same as `isOwned` —
    /// a reference in an owned shop carries no `XOWN` and is still theft, and
    /// a faction-owned chest the player ranks high enough in is not.
    public let isTheft: Bool
    /// What taking it would add to the bounty, in gold. Zero when the take is
    /// no crime, and also when the place answers to no crime faction.
    public let bounty: Int32

    public init(
        name: String,
        reference: FormID,
        owner: FormID?,
        factionRank: Int32?,
        isTheft: Bool = false,
        bounty: Int32 = 0
    ) {
        self.name = name
        self.reference = reference
        self.owner = owner
        self.factionRank = factionRank
        self.isTheft = isTheft
        self.bounty = bounty
    }

    /// Whether the reference record itself names an owner.
    public var isOwned: Bool {
        owner != nil
    }
}

/// What one actor is wearing, and what its appearance resolution left out.
nonisolated public struct EquipInspectReadout: Equatable, Sendable {
    /// The holder's display name, or nil when nothing resolves the selected
    /// target — no player inventory, or no resident actor.
    public let name: String?
    /// The equipped set, with the slots and hands each piece occupies.
    public let equipped: [EquippedItemReadout]
    /// `AppearanceSkip` lines for this actor from the last build of its cell,
    /// already stripped of the "ACHR <id>: " prefix. Always empty for the
    /// player, who has no rendered body until M14.
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
    /// What the session's resolved-enchantment cache holds and how much of it
    /// has been reused (issue #489).
    ///
    /// A session-wide reading on an owner-scoped section, because this is where
    /// the enchantment lines it feeds are read: the equipped set above names
    /// what each piece carries, and this says how many times that answer was
    /// reused rather than re-walked out of the records.
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
