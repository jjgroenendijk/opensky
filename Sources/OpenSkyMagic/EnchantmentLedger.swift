// Reads and writes one owner's `EnchantedItemState` through `WorldStateStore.set`.
// Charge math is in `EnchantmentCharge`, record resolution in `ItemEnchantmentProfile`.
// Nothing throws: an unspent item reads its full record charge.
// See docs/engine/item-enchantments.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyWorldState

@MainActor
public struct EnchantmentLedger {
    public let store: WorldStateStore

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
        guard let remaining = state(of: holder).charge(of: profile.item) else {
            return profile.fullCharge
        }
        return profile.charge(remaining: remaining)
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
        write(state(of: holder).setting(charge: after.remaining, of: profile.item), for: holder)
        return after
    }

    /// Restores `profile`'s item to full charge and stops recording it. Not a soul gem:
    /// recharging is not modelled. For the dev control and tests.
    public func recharge(_ profile: ItemEnchantmentProfile, on holder: ActorValueHolder) {
        write(state(of: holder).clearingCharge(of: profile.item), for: holder)
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

    public init(store: WorldStateStore) {
        self.store = store
    }
}
