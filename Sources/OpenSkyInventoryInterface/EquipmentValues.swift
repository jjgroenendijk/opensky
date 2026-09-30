import Foundation
import OpenSkyFormatsESM

/// Failures the equipment layer reports. Like `InventoryError`, every one is a
/// caller mistake rather than malformed input.
nonisolated public enum EquipmentError: Error, Equatable {
    /// The owner does not hold the item it was asked to equip.
    case notHeld(item: FormID, owner: ReferenceKey)
    /// No loaded plugin describes the item as occupying any slot or hand, so
    /// there is nothing for equipping it to mean.
    case notEquippable(item: FormID)
}

/// What one equip changed: the item now worn and everything it displaced.
nonisolated public struct EquipmentChange: Equatable, Sendable {
    /// Items unequipped to make room, in ascending FormID order. Empty when
    /// nothing conflicted.
    public let unequipped: [FormID]
    /// False when the item was already equipped and displaced nothing, so the
    /// stored state is byte-identical and no rebuild is needed.
    public let changed: Bool

    public init(unequipped: [FormID], changed: Bool) {
        self.unequipped = unequipped
        self.changed = changed
    }
}
