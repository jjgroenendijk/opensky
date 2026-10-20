// Reads and writes an item's charge: on its best held copy when an inventory holds it,
// else in the owner's `EnchantedItemState`. Charge math is in `EnchantmentCharge`.
// Nothing throws: an unspent item reads its full record charge.
// See docs/engine/item-enchantments.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyWorldState

@MainActor
public struct EnchantmentLedger {
    public let store: WorldStateStore
    /// Holds the charge per copy. Without it, or for an item the owner does not hold,
    /// the charge is kept per base item.
    public let inventory: (any InventoryAccess)?

    // MARK: - Reading

    /// `holder`'s enchanted-item state, empty when it has none.
    public func state(of holder: ActorValueHolder) -> EnchantedItemState {
        store.component(EnchantedItemState.self, for: holder.key) ?? EnchantedItemState()
    }

    /// What `profile`'s item has left on `holder`: the stored charge where
    /// something has spent some, and the record's own full charge otherwise.
    public func charge(of profile: ItemEnchantmentProfile, on holder: ActorValueHolder)
        -> EnchantmentCharge
    {
        let stored = bestCopy(of: profile.item, on: holder)?.charge
            ?? state(of: holder).charge(of: profile.item)
        return stored.map(profile.charge(remaining:)) ?? profile.fullCharge
    }

    private func bestCopy(of item: FormID, on holder: ActorValueHolder) -> ItemCopy? {
        inventory?.copies(of: item, in: InventoryHolder(actor: holder)).first
    }

    // MARK: - Mutating

    /// Spends one use of `profile`'s charge on `holder`.
    ///
    /// - Returns: the charge after the hit, or nil when it could not pay — which
    ///   is what an empty weapon is, and the caller then applies nothing.
    @discardableResult
    public func spend(_ profile: ItemEnchantmentProfile, on holder: ActorValueHolder)
        -> EnchantmentCharge?
    {
        let before = charge(of: profile, on: holder)
        guard let after = before.spending() else { return nil }
        // An unmetered enchantment spends nothing, so it writes nothing: an item
        // whose record charges no magicka must not make its owner dirty on every
        // swing for a number that never changes.
        guard after != before else { return after }
        setCharge(after.remaining, of: profile.item, on: holder)
        return after
    }

    /// Puts `amount` of charge back into `profile`'s item, capped at its capacity.
    /// A full item stops being recorded.
    @discardableResult
    public func recharge(
        _ profile: ItemEnchantmentProfile,
        by amount: Float = .infinity,
        on holder: ActorValueHolder
    ) -> EnchantmentCharge {
        let before = charge(of: profile, on: holder)
        let remaining = min(before.capacity, before.remaining + max(0, amount))
        setCharge(remaining >= before.capacity ? nil : remaining, of: profile.item, on: holder)
        return before.restoring(to: remaining)
    }

    /// Stores `remaining` on the best held copy, or per base item when `holder`
    /// holds none. Nil means full.
    private func setCharge(_ remaining: Float?, of item: FormID, on holder: ActorValueHolder) {
        let state = state(of: holder)
        let onCopy = inventory?.editCopy(
            of: item, in: InventoryHolder(actor: holder), where: { _ in true },
            { $0.charge = remaining }
        ) == true
        if onCopy {
            if state.charge(of: item) != nil {
                write(state.clearingCharge(of: item), for: holder)
            }
        } else if let remaining {
            write(state.setting(charge: remaining, of: item), for: holder)
        } else {
            write(state.clearingCharge(of: item), for: holder)
        }
    }

    /// Records that `item` established `sequences` while worn on `holder`. An
    /// empty list forgets the item.
    public func setWornEffects(
        _ sequences: [UInt64],
        of item: FormID,
        on holder: ActorValueHolder
    ) {
        write(state(of: holder).setting(wornEffects: sequences, of: item), for: holder)
    }

    /// Stores `state`, dropping the whole component once it is empty so an owner
    /// whose weapons are full and whose worn items grant nothing stops being
    /// dirty for this slot.
    public func write(_ state: EnchantedItemState, for holder: ActorValueHolder) {
        if state.isEmpty {
            store.reset(.enchantedItems, for: holder.key)
        } else {
            store.set(state, for: holder.key, in: holder.cell)
        }
    }

    public init(store: WorldStateStore, inventory: (any InventoryAccess)? = nil) {
        self.store = store
        self.inventory = inventory
    }
}
