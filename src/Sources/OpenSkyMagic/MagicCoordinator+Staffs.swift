// The staff in an actor's right hand, its enchantment as a spell, and its charge.
// OpenSky equips every one-handed weapon in the right hand, so only that hand holds a
// staff. See docs/engine/spellcasting.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

extension MagicCoordinator.CasterBridge {
    func staffSpell(in hand: SpellHand, of holder: ActorValueHolder) -> ResolvedSpell? {
        coordinator.heldStaves.heldStaff(of: holder, in: hand)?.spell
    }

    /// An unmetered staff never runs dry.
    func staffCharge(of spell: ResolvedSpell, on holder: ActorValueHolder) -> Float {
        guard
            let staff = coordinator.heldStaves.heldStaff(of: holder, in: .right),
            staff.spell.key == spell.key,
            let runtime = coordinator.effects
        else { return 0 }
        let charge = EnchantmentLedger(store: runtime.store, inventory: coordinator.world.inventory)
            .charge(of: staff.profile, on: holder)
        return charge.isMetered ? charge.remaining : .infinity
    }

    func spendStaffCharge(
        _ amount: Float, of spell: ResolvedSpell, on holder: ActorValueHolder
    ) {
        guard
            let staff = coordinator.heldStaves.heldStaff(of: holder, in: .right),
            staff.spell.key == spell.key,
            let runtime = coordinator.effects
        else { return }
        EnchantmentLedger(store: runtime.store, inventory: coordinator.world.inventory)
            .drain(staff.profile, by: amount, on: holder)
    }
}
