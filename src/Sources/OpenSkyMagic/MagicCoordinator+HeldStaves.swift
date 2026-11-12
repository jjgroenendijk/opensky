// The staff in an actor's hand, with its enchantment and the charge it has left.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

extension MagicCoordinator.HeldStaves {
    /// The staff `holder` holds in `hand`, or nil.
    func heldStaff(of holder: ActorValueHolder, in hand: SpellHand) -> HeldStaff? {
        guard
            hand == .right, let equipment = coordinator.world.equipment,
            let store = coordinator.enchantmentStore,
            let items = coordinator.world.inventory?.baselines.items
        else { return nil }
        let owner = InventoryHolder(actor: holder)
        for item in equipment.equipped(on: owner) {
            guard
                let profile = coordinator.weaponEnchantments.enchantmentProfile(
                    of: item,
                    on: owner
                ),
                profile.isStaff,
                let id = items.definition(item)?.enchantment?.resolvedID,
                let enchantment = store.enchantment(id)
            else { continue }
            return HeldStaff(profile: profile, spell: enchantment.staffSpell)
        }
        return nil
    }

    /// The player's staff for a readout: the item, its enchantment, and its charge.
    func playerStaff() -> (staff: HeldStaff, charge: EnchantmentCharge)? {
        guard
            let staff = heldStaff(of: .player, in: .right), let runtime = coordinator.effects
        else { return nil }
        let charge = EnchantmentLedger(store: runtime.store, inventory: coordinator.world.inventory)
            .charge(of: staff.profile, on: .player)
        return (staff, charge)
    }
}
