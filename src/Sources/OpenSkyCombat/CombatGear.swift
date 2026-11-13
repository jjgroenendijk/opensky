// The player's gear in combat: the readied hands, the worn items, the arrow, and the
// bow zoom. Eagle Eye's `Mod Bow Zoom` sets the view
// share, its bow `Mod Power Attack Stamina` the drain per second, and Steady Hand's
// `Bow Speed Bonus` the time scale while zoomed. See docs/engine/archery.md.

import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension CombatShared {
    /// The player's hands, worn items, arrows, and bow zoom, read from the world.
    struct CombatGear {
        let shared: CombatShared

        func readiedHands() -> ReadiedHands {
            ReadiedHands(
                right: shared.world.gearReads.hasReadiedSpell(in: .right),
                left: shared.world.gearReads.hasReadiedSpell(in: .left)
            )
        }

        func wornItems() -> [CombatWornItem] {
            guard
                let equipment = shared.world.gearReads.equipment,
                let items = shared.items else { return [] }
            return equipment.equipped(on: .player).map { item in
                if let weapon = items.weapon(item) {
                    let enchantment = shared.world.gearReads.enchantmentProfile(of: item)
                    return .weapon(MeleeWeaponProfile(weapon: weapon, enchantment: enchantment)
                        .tempered(level: shared.world.gearReads.temperLevel(of: item)))
                }
                return equipment.occupancy(of: item).slots.contains(.shield) ? .shield : .other
            }
        }

        /// The first weapon the player has equipped, or nil when unarmed.
        func playerWeapon() -> Weapon? {
            guard
                let equipment = shared.world.gearReads.equipment,
                let items = shared.items else { return nil }
            return equipment.equipped(on: .player).lazy.compactMap { items.weapon($0) }.first
        }

        func selectedArrow() -> ArcheryAmmunition? {
            guard let items = shared.items else { return nil }
            return CombatCore.arrow(
                equipped: shared.world.gearReads.equipment?.equipped(on: .player) ?? [],
                carried: shared.world.gearReads.playerCarriedItems(),
                resolve: items.archeryAmmunition
            )
        }

        func archeryAttackMultiplier() -> Float {
            guard let values = shared.world.actorValues(of: .player) else { return 1 }
            return CombatFortifyBonus.archery(reading: values)
        }

        /// What the zoom reads this frame besides the keys.
        func bowZoomConditions(bow: FormID?) -> BowZoomInput {
            let stamina = ActorValueIdentity.index(named: "Stamina")
                .flatMap { shared.world.actorValues(of: .player)?($0) }
            return BowZoomInput(
                viewShare: shared.perks.bowZoomViewShare(bow: bow),
                hasStamina: (stamina ?? 1) >= 1,
                timeIsSlowed: shared.isTimeSlowed
            )
        }

        /// Eagle Eye sets the bow's power attack stamina, and UESP gives the zoom drain as
        /// that much per second. Regeneration stays held while zoomed and for
        /// `fBowZoomStaminaRegenDelay` after.
        func drainBowZoomStamina(bow: FormID?, delta: Float) {
            guard shared.archery?.zoom.isZoomed == true, delta > 0 else { return }
            shared.world.pauseBowZoomStamina()
            let base = shared.archery?.settings.bowZoomStaminaDrain ?? 0
            let perSecond = shared.perks.powerAttackStamina(base, weapon: bow)
            guard perSecond > 0, perSecond.isFinite else { return }
            shared.world.damageStamina(by: perSecond * delta, of: .player)
        }

        /// The world's and the player's share of normal speed: `Bow Speed Bonus` while
        /// zoomed, which Steady Hand lowers, else 1.
        var bowZoomTimeScale: Float {
            guard
                shared.archery?.zoom.isZoomed == true,
                let bonus = shared.world.actorValues(of: .player)?(ActorValueIndex.bowSpeedBonus),
                bonus.isFinite, bonus > 0
            else { return 1 }
            return min(bonus, 1)
        }
    }
}
