// Equip and unequip (issue #178, roadmap item 12.2.1): the layer that turns
// "wear this" into one journalled write on the owner's inventory component.
//
// #176 gave `ReferenceInventoryState` an equipped set and deliberately left it
// as storage — `InventoryRuntime.equip` inserts a FormID and nothing arbitrates.
// This is the arbitration. Equipping an item unequips everything it conflicts
// with (`EquipmentOccupancy.conflicts(with:)`), so the equipped set is always
// internally consistent: no two members ever claim the same biped slot or the
// same hand.
//
// A thin layer over `InventoryRuntime` for the same reason that one is a thin
// layer over `WorldStateStore`: equipping needs an `EquipmentCatalog` for slot
// data, which the inventory layer has no business holding. Every change goes
// through `InventoryRuntime.setEquipped`, so it lands in the journal, in the
// dirty counts and in the save exactly like a take or a drop does — and, being
// a component write attributed to the owner's cell, it also raises the cell
// rebuild that makes the change visible (`CellStreamer.noteStateMutation`).
//
// Two rules the API refuses rather than works around:
//
// * Equipping something the owner does not hold is a typed failure. Silently
//   equipping an item out of nowhere is how a duplication bug hides, and no
//   caller in this engine has a legitimate reason to do it — give the item
//   first, then equip it.
// * Equipping something with no slots at all is a typed failure. A potion
//   conflicts with nothing, so it would otherwise accumulate in the equipped
//   set forever and never be taken back out by any conflict.
//
// The player goes through this same API. It mutates the player's equipped set
// and, through it, nothing about carry weight — equipped items stay carried, so
// `InventoryRuntime.carriedWeight` already counts them and equipping changes
// no number. The player has no rendered body this milestone (M14), so there is
// nothing else for the player path to do.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// Failures the equipment layer reports. Like `InventoryError`, every one is a
/// caller mistake rather than malformed input.
nonisolated enum EquipmentError: Error, Equatable {
    /// The owner does not hold the item it was asked to equip.
    case notHeld(item: FormID, owner: ReferenceKey)
    /// No loaded plugin describes the item as occupying any slot or hand, so
    /// there is nothing for equipping it to mean.
    case notEquippable(item: FormID)
}

/// What one equip changed: the item now worn and everything it displaced.
nonisolated struct EquipmentChange: Equatable, Sendable {
    let equipped: FormID
    /// Items unequipped to make room, in ascending FormID order. Empty when
    /// nothing conflicted.
    let unequipped: [FormID]
    /// False when the item was already equipped and displaced nothing, so the
    /// stored state is byte-identical and no rebuild is needed.
    let changed: Bool
}

/// Equips and unequips items on top of an `InventoryRuntime`.
@MainActor
struct EquipmentRuntime {
    let inventory: InventoryRuntime
    let catalog: EquipmentCatalog

    // MARK: - Reading

    /// `holder`'s equipped set, from its runtime component when it has one and
    /// from its plugin baseline when it does not.
    func equipped(on holder: InventoryHolder) -> [FormID] {
        inventory.inventory(of: holder).equipped
    }

    func isEquipped(_ item: FormID, on holder: InventoryHolder) -> Bool {
        inventory.inventory(of: holder).isEquipped(item)
    }

    /// What `item` occupies, for a caller that wants to explain a conflict
    /// before causing one.
    func occupancy(of item: FormID) -> EquipmentOccupancy {
        catalog.occupancy(of: item)
    }

    // MARK: - Mutating

    /// Equips `item` on `holder`, unequipping whatever it conflicts with.
    ///
    /// The whole resulting equipped set is computed before anything is written,
    /// so a refused equip leaves the store untouched and an accepted one is a
    /// single journal entry rather than one per displaced piece.
    ///
    /// - Returns: what changed, including the items that were displaced.
    /// - Throws: `EquipmentError.notHeld` when the owner does not hold the
    ///   item, `EquipmentError.notEquippable` when it occupies no slot.
    @discardableResult
    func equip(_ item: FormID, on holder: InventoryHolder) throws -> EquipmentChange {
        let state = inventory.inventory(of: holder)
        guard state.count(of: item) > 0 else {
            throw EquipmentError.notHeld(item: item, owner: holder.key)
        }
        let incoming = catalog.occupancy(of: item)
        guard !incoming.isEmpty else {
            throw EquipmentError.notEquippable(item: item)
        }
        let displaced = state.equipped.filter {
            $0 != item && catalog.occupancy(of: $0).conflicts(with: incoming)
        }
        let resolved = state.equipped.filter { !displaced.contains($0) } + [item]
        let changed = inventory.setEquipped(resolved, on: holder)
        return EquipmentChange(equipped: item, unequipped: displaced, changed: changed)
    }

    /// Unequips `item` on `holder`. Unequipping something that is not equipped
    /// changes nothing and is not an error: the caller asked for a state, and
    /// that state already holds.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    func unequip(_ item: FormID, on holder: InventoryHolder) -> Bool {
        inventory.unequip(item, on: holder)
    }

    /// Unequips everything `holder` wears.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    func unequipAll(on holder: InventoryHolder) -> Bool {
        inventory.setEquipped([], on: holder)
    }
}
