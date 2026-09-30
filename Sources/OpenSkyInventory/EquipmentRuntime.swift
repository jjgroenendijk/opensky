// Equip and unequip: one journalled write on the owner's inventory component.
// Equipping unequips every conflict (`EquipmentOccupancy.conflicts(with:)`), so
// no two items claim a slot or hand. Writes go through
// `InventoryRuntime.setEquipped`. Equipping an item not held, or one with no
// slots, is a typed failure. See docs/engine/inventory-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// Equips and unequips items on top of an `InventoryRuntime`.
@MainActor
public struct EquipmentRuntime: EquipmentAccess {
    public let inventory: InventoryRuntime
    public let catalog: EquipmentCatalog

    // MARK: - Reading

    /// `holder`'s equipped set, from its runtime component when it has one and
    /// from its plugin baseline when it does not.
    public func equipped(on holder: InventoryHolder) -> [FormID] {
        inventory.inventory(of: holder).equipped
    }

    public func isEquipped(_ item: FormID, on holder: InventoryHolder) -> Bool {
        inventory.inventory(of: holder).isEquipped(item)
    }

    /// What `item` occupies, for a caller that wants to explain a conflict
    /// before causing one.
    public func occupancy(of item: FormID) -> EquipmentOccupancy {
        catalog.occupancy(of: item)
    }

    // MARK: - Mutating

    /// Equips `item` on `holder`, unequipping its conflicts. The whole new set is
    /// computed first, so a refusal writes nothing and success is one journal entry.
    /// - Returns: what changed, including the displaced items.
    /// - Throws: `EquipmentError.notHeld`, `EquipmentError.notEquippable`.
    @discardableResult
    public func equip(_ item: FormID, on holder: InventoryHolder) throws -> EquipmentChange {
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
        return EquipmentChange(unequipped: displaced, changed: changed)
    }

    /// Unequips `item` on `holder`. Unequipping something that is not equipped
    /// changes nothing and is not an error: the caller asked for a state, and
    /// that state already holds.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    public func unequip(_ item: FormID, on holder: InventoryHolder) -> Bool {
        inventory.unequip(item, on: holder)
    }

    /// Unequips everything `holder` wears.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    public func unequipAll(on holder: InventoryHolder) -> Bool {
        inventory.setEquipped([], on: holder)
    }

    public init(inventory: InventoryRuntime, catalog: EquipmentCatalog) {
        self.inventory = inventory
        self.catalog = catalog
    }
}
