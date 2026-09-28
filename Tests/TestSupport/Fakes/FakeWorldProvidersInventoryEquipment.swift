// The Inventory & Equipment half of the world-provider fake (issue #180), in
// its own file so `FakeWorldProviders` stays inside the lint caps.
//
// The fake keeps a real two-inventory ledger rather than canned strings,
// because the section under test is an accounting readout: a grant that does
// not change what the next snapshot reports would let the panel pass while
// showing a number nothing produced.

@testable import opensky

/// The fake's inventory-and-equipment ledger, kept together so
/// `FakeWorldProviders` spends one stored property on it.
struct FakeInventoryEquipmentState {
    var isAvailable = true
    var target = EquipmentTargetSelector.nearestActor
    var containerIsOpen = false
    var playerCount: Int32 = 1
    var containerCount: Int32 = 0
    var lastAction = "No grant yet."
    var ownership: ReferenceOwnershipReadout? = ReferenceOwnershipReadout(
        name: "Iron Sword", reference: FormID(0x0700), owner: nil, factionRank: nil
    )
}

extension FakeWorldProviders {
    static let grantedSword = FormID(0x0200)
    static let unknownItem = FormID(0xDEAD)

    var inventoryEquipmentInspectionTarget: EquipmentTargetSelector {
        get { inventoryEquipment.target }
        set { inventoryEquipment.target = newValue }
    }

    @discardableResult
    func grantItem(_ item: FormID, count: Int32, to target: InventoryGrantTarget) -> String {
        guard count > 0 else {
            inventoryEquipment.lastAction = "Grant refused: a count of \(count) is not a stack."
            return inventoryEquipment.lastAction
        }
        guard item != Self.unknownItem else {
            inventoryEquipment.lastAction = "Grant refused: no loaded plugin describes \(item)."
            return inventoryEquipment.lastAction
        }
        guard target == .player || inventoryEquipment.containerIsOpen else {
            inventoryEquipment.lastAction = "Grant refused: no container is open."
            return inventoryEquipment.lastAction
        }
        switch target {
        case .player: inventoryEquipment.playerCount += count
        case .openContainer: inventoryEquipment.containerCount += count
        }
        inventoryEquipment.lastAction = "Granted \(count) × IronSword to \(target.label)."
        return inventoryEquipment.lastAction
    }

    var inventoryEquipmentSnapshot: InventoryEquipmentSnapshot {
        guard inventoryEquipment.isAvailable else { return .unavailable }
        return InventoryEquipmentSnapshot(
            isAvailable: true,
            hasOpenContainer: inventoryEquipment.containerIsOpen,
            openContainerName: inventoryEquipment.containerIsOpen ? "Test Chest" : nil,
            playerStacks: [ItemStackReadout(
                item: Self.grantedSword, count: inventoryEquipment.playerCount, name: "IronSword"
            )],
            playerGold: 42,
            playerWeight: 9 * Float(inventoryEquipment.playerCount),
            containerStacks: inventoryEquipment.containerIsOpen
                ? [ItemStackReadout(
                    item: Self.grantedSword,
                    count: inventoryEquipment.containerCount,
                    name: "IronSword"
                )]
                : [],
            containerGold: inventoryEquipment.containerIsOpen ? 500 : 0,
            targetOwnership: inventoryEquipment.ownership,
            equipTarget: inventoryEquipment.target,
            equipInspection: inventoryEquipmentInspection,
            // One item resolved and reused every frame since, which is the
            // shape a live session's cache reads (issue #489).
            enchantmentCache: EnchantmentCacheReadout(
                itemCount: 1, resolvedCount: 1, reuseCount: 12
            ),
            lastActionText: inventoryEquipment.lastAction
        )
    }

    /// What the fake reports for the inspected owner. The NPC carries a skip so
    /// a test can tell the two owners apart by their readout alone.
    private var inventoryEquipmentInspection: EquipInspectReadout {
        switch inventoryEquipment.target {
        case .player:
            EquipInspectReadout(
                name: "the player",
                equipped: [],
                appearanceSkips: [],
                usesRuntimeEquipment: false
            )
        case .nearestActor:
            EquipInspectReadout(
                name: "00003000 (base 00003000)",
                equipped: [EquippedItemReadout(
                    item: Self.grantedSword, name: "IronSword", occupancy: "right hand",
                    // Item 19.9 gave the readout an enchantment line; the fake
                    // carries one so the M19 gate can read a charge back through
                    // the panel rather than only through the formatter.
                    enchantment: "Fire Damage (on hit) · 2926/3000 charge, 79 use(s) left"
                )],
                appearanceSkips: ["maskedByOutfit (00000300)"],
                usesRuntimeEquipment: true
            )
        }
    }
}
