// The seams other features reach inventories and equipment through.
// `InventoryRuntime` and `EquipmentRuntime` conform, and the composition root
// hands them over as these protocols.

import OpenSkyFormatsESM
import OpenSkyGameData

/// Counts, gold, and stolen goods in one holder's inventory, over the
/// world-state store.
@MainActor
public protocol InventoryAccess {
    /// The plugin baselines behind every inventory, and the item index.
    var baselines: InventoryBaselineResolver { get }

    /// The gold item, `Gold001` in vanilla.
    var goldFormID: FormID { get }

    /// `holder`'s inventory, from its runtime component when it has one and
    /// from its plugin baseline when it does not.
    func inventory(of holder: InventoryHolder) -> ReferenceInventoryState

    /// How many of `item` `holder` carries.
    func count(of item: FormID, in holder: InventoryHolder) -> Int32

    /// How much gold `holder` carries.
    func goldCount(of holder: InventoryHolder) -> Int32

    /// Takes `count` of `item` out of `holder`.
    ///
    /// - Throws: `InventoryError` when `holder` has fewer, which writes nothing.
    @discardableResult
    func remove(_ item: FormID, count: Int32, from holder: InventoryHolder) throws
        -> ReferenceInventoryState

    /// Moves every stolen stack from `source` to `destination`.
    func confiscateStolen(
        from source: InventoryHolder,
        to destination: InventoryHolder
    ) throws -> [InventoryStack]
}

/// Equips and unequips items, with the hand and slot conflicts resolved.
@MainActor
public protocol EquipmentAccess {
    /// `holder`'s equipped items.
    func equipped(on holder: InventoryHolder) -> [FormID]

    func isEquipped(_ item: FormID, on holder: InventoryHolder) -> Bool

    /// What `item` occupies.
    func occupancy(of item: FormID) -> EquipmentOccupancy

    /// Equips `item` on `holder`, unequipping whatever it conflicts with.
    ///
    /// - Throws: `EquipmentError` when the item is not held or occupies no slot.
    @discardableResult
    func equip(_ item: FormID, on holder: InventoryHolder) throws -> EquipmentChange

    /// Unequips `item` on `holder`. Returns true when the stored state changed.
    @discardableResult
    func unequip(_ item: FormID, on holder: InventoryHolder) -> Bool
}
