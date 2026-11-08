// The staff in an actor's right hand, its enchantment as a spell, and its charge.
// OpenSky equips every one-handed weapon in the right hand, so only that hand holds a
// staff. See docs/engine/spellcasting.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface

extension MagicCoordinator: StaffCharging {
    public func staffSpell(in hand: SpellHand, of holder: ActorValueHolder) -> ResolvedSpell? {
        heldStaff(of: holder, in: hand)?.spell
    }

    /// An unmetered staff never runs dry.
    public func staffCharge(of spell: ResolvedSpell, on holder: ActorValueHolder) -> Float {
        guard
            let staff = heldStaff(of: holder, in: .right), staff.spell.key == spell.key,
            let runtime = effects
        else { return 0 }
        let charge = EnchantmentLedger(store: runtime.store, inventory: world.inventory)
            .charge(of: staff.profile, on: holder)
        return charge.isMetered ? charge.remaining : .infinity
    }

    public func spendStaffCharge(
        _ amount: Float, of spell: ResolvedSpell, on holder: ActorValueHolder
    ) {
        guard
            let staff = heldStaff(of: holder, in: .right), staff.spell.key == spell.key,
            let runtime = effects
        else { return }
        EnchantmentLedger(store: runtime.store, inventory: world.inventory)
            .drain(staff.profile, by: amount, on: holder)
    }

    /// The staff `holder` holds in `hand`, or nil.
    public func heldStaff(of holder: ActorValueHolder, in hand: SpellHand) -> HeldStaff? {
        guard
            hand == .right, let equipment = world.equipment, let store = enchantmentStore,
            let items = world.inventory?.baselines.items
        else { return nil }
        let owner = InventoryHolder(actor: holder)
        for item in equipment.equipped(on: owner) {
            guard
                let profile = enchantmentProfile(of: item, on: owner), profile.isStaff,
                let id = items.definition(item)?.enchantment?.resolvedID,
                let enchantment = store.enchantment(id)
            else { continue }
            return HeldStaff(profile: profile, spell: enchantment.staffSpell)
        }
        return nil
    }

    /// The player's staff for a readout: the item, its enchantment, and its charge.
    public func playerStaff() -> (staff: HeldStaff, charge: EnchantmentCharge)? {
        guard
            let staff = heldStaff(of: .player, in: .right), let runtime = effects
        else { return nil }
        let charge = EnchantmentLedger(store: runtime.store, inventory: world.inventory)
            .charge(of: staff.profile, on: .player)
        return (staff, charge)
    }
}
