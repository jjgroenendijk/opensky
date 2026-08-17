// The stored half of enchanted-item state (issue #472, roadmap item 19.9):
// reading and writing one owner's `EnchantedItemState` through the world-state
// store.
//
// A thin layer beside `WorldStateStore`, following the `InventoryRuntime`,
// `ActorValueRuntime` and `ActiveEffectRuntime` precedent: every mutation writes
// through `WorldStateStore.set`, so it lands in the journal, in the dirty counts
// and in the save. The store is the generic substrate that knows about keys and
// components and deliberately knows nothing about records, which is why the
// charge arithmetic lives in `EnchantmentCharge` and the record resolution in
// `ItemEnchantmentProfile`.
//
// Headless and AppKit-free, so it compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the store it writes to is.
//
// Failure model: nothing here throws. An item nobody has spent charge on reads
// its record's full charge, and an owner with nothing enchanted has no component
// at all.
//
// Documented in docs/engine/magic.md.

import Foundation

@MainActor
struct EnchantmentLedger {
    let store: WorldStateStore

    // MARK: - Reading

    /// `holder`'s enchanted-item state, empty when it has none.
    func state(of holder: ActorValueHolder) -> EnchantedItemState {
        store.component(EnchantedItemState.self, for: holder.key) ?? EnchantedItemState()
    }

    /// What `profile`'s item has left on `holder`: the stored charge where
    /// something has spent some, and the record's own full charge otherwise.
    func charge(of profile: ItemEnchantmentProfile, on holder: ActorValueHolder)
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
    func spend(_ profile: ItemEnchantmentProfile, on holder: ActorValueHolder)
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

    /// Puts `profile`'s item back to full charge and stops recording it, so it
    /// reads as its record authored it again.
    ///
    /// Not a soul gem: recharging is out of item 19.9's scope and an empty weapon
    /// stays empty. This exists for the dev control and for a test that needs a
    /// fresh weapon.
    func recharge(_ profile: ItemEnchantmentProfile, on holder: ActorValueHolder) {
        write(state(of: holder).clearingCharge(of: profile.item), for: holder)
    }

    /// Records that `item` established `sequences` while worn on `holder`. An
    /// empty list forgets the item.
    func setWornEffects(
        _ sequences: [UInt64],
        of item: FormID,
        on holder: ActorValueHolder
    ) {
        write(state(of: holder).setting(wornEffects: sequences, of: item), for: holder)
    }

    /// Stores `state`, dropping the whole component once it is empty so an owner
    /// whose weapons are full and whose worn items grant nothing stops being
    /// dirty for this slot.
    func write(_ state: EnchantedItemState, for holder: ActorValueHolder) {
        if state.isEmpty {
            store.reset(.enchantedItems, for: holder.key)
        } else {
            store.set(state, for: holder.key, in: holder.cell)
        }
    }
}
