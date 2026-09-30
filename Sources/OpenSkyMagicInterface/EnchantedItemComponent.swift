// Per-item enchantment state as a world-state component: each enchanted weapon's
// remaining charge, and the constant effects each worn item established. Charge
// is keyed by base FormID, because items have no per-instance identity yet, so
// two identical weapons share one charge. Worn effects are recorded by
// `ActiveEffect.sequence`, so removal is exact.
// See docs/engine/item-enchantments.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One owner's enchanted-item bookkeeping: charge left per weapon, and the
/// constant effects each worn item established.
nonisolated public struct EnchantedItemState: WorldStateComponent, Sendable {
    /// Remaining charge per item, keyed by base FormID. Absent means "as the
    /// record authored it" — a full weapon writes nothing, exactly as an
    /// undamaged actor writes no actor values.
    public private(set) var charges: [UInt32: Float]
    /// The `ActiveEffect` sequences each worn item's enchantment established,
    /// keyed by base FormID and kept ascending so re-encoding is stable.
    public private(set) var wornEffects: [UInt32: [UInt64]]

    public static var componentKind: WorldStateComponentKind {
        .enchantedItems
    }

    /// Normalizes on the way in, which is what makes this the save decoder's
    /// entry point too: a non-finite charge becomes zero, a negative one
    /// becomes zero, and an item recorded as wearing no effects at all is
    /// dropped rather than kept as an empty list.
    public init(charges: [UInt32: Float] = [:], wornEffects: [UInt32: [UInt64]] = [:]) {
        self.charges = charges.mapValues { $0.isFinite ? max(0, $0) : 0 }
        self.wornEffects = wornEffects
            .filter { !$0.value.isEmpty }
            .mapValues { $0.sorted() }
    }

    public var isEmpty: Bool {
        charges.isEmpty && wornEffects.isEmpty
    }

    // MARK: - Queries

    /// The charge recorded for `item`, or nil when nothing has spent any.
    public func charge(of item: FormID) -> Float? {
        charges[item.rawValue]
    }

    /// The effects `item` established while worn, ascending. Empty when it
    /// established none or is not worn.
    public func wornEffects(of item: FormID) -> [UInt64] {
        wornEffects[item.rawValue] ?? []
    }

    /// Every item recorded as wearing effects, in ascending FormID order.
    public var wornItems: [FormID] {
        wornEffects.keys.sorted().map(FormID.init(_:))
    }

    /// Every sequence any worn item established, which is what a wholesale
    /// removal — an `unequipAll`, a load — dispels.
    public var allWornSequences: Set<UInt64> {
        Set(wornEffects.values.joined())
    }

    // MARK: - Mutations

    /// This state with `item`'s charge recorded as `amount`.
    public func setting(charge amount: Float, of item: FormID) -> EnchantedItemState {
        var updated = charges
        updated[item.rawValue] = amount
        return EnchantedItemState(charges: updated, wornEffects: wornEffects)
    }

    /// This state with `item`'s charge forgotten, so it reads as the record
    /// authored it again.
    public func clearingCharge(of item: FormID) -> EnchantedItemState {
        var updated = charges
        updated.removeValue(forKey: item.rawValue)
        return EnchantedItemState(charges: updated, wornEffects: wornEffects)
    }

    /// This state recording that `item` established `sequences` while worn.
    /// An empty list removes the record, which is what unequipping means.
    public func setting(wornEffects sequences: [UInt64], of item: FormID) -> EnchantedItemState {
        var updated = wornEffects
        if sequences.isEmpty {
            updated.removeValue(forKey: item.rawValue)
        } else {
            updated[item.rawValue] = sequences
        }
        return EnchantedItemState(charges: charges, wornEffects: updated)
    }
}

nonisolated extension WorldStateComponentKind {
    /// One owner's enchanted items: charge left per weapon, and the constant
    /// effects each worn piece established. A slot of its own rather than fields on
    /// `inventory` for the lifetime reason `activeEffects` is separate from
    /// `actorValues`: the inventory component is rewritten by every take, drop and
    /// equip, while charge moves only when an enchanted weapon actually lands a
    /// hit.
    public static let enchantedItems = Self(rawValue: "enchantedItems", order: 14)
}
