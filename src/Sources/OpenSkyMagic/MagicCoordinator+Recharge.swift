// Putting charge back into an enchanted weapon: a soul gem the player spends, or Soul
// Siphon's share of a creature's soul at a killing blow. The charge goes on the
// weapon's best copy. See docs/engine/item-enchantments.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// What one recharge did.
nonisolated enum RechargeOutcome: Equatable, Sendable {
    case recharged(item: FormID, gem: FormID, charge: EnchantmentCharge)
    /// The player has no equipped enchanted weapon that is short of charge.
    case nothingToRecharge
    case noFilledGem
    case unavailable
}

extension MagicCoordinator.WeaponRecharge {
    /// Recharges the player's equipped weapon from the smallest filled gem that fills
    /// it, or the largest gem when none does.
    @discardableResult
    func rechargeEquippedWeapon() -> RechargeOutcome {
        guard let runtime = coordinator.effects, let inventory = coordinator.world.inventory else {
            return .unavailable
        }
        guard let weapon = coordinator.soulTrapping.rechargeableWeapon(on: .player, staves: true)
        else {
            return .nothingToRecharge
        }
        let missing = weapon.charge.capacity - weapon.charge.remaining
        let worth = { (gem: SoulGemCandidate) in
            self.gemRechargeAmount(gem.soul, for: weapon.profile.item)
        }
        let filled = coordinator.soulTrapping.carriedGems(inventory).filter { $0.soul != .empty }
        let fitting = filled.filter { worth($0) >= missing }
        guard
            let gem = fitting.min(by: { worth($0) < worth($1) })
            ?? filled.max(by: { worth($0) < worth($1) })
        else { return .noFilledGem }
        let amount = worth(gem)
        coordinator.enchantingTable.spendGem(gem, in: inventory)
        coordinator.enchantingRecords
            .reportEnchantingUse(
                coordinator.rules.enchanting.rechargeExperience(charge: SoulTrap.charge(of: gem.soul))
            )
        let charge = EnchantmentLedger(store: runtime.store, inventory: inventory)
            .recharge(weapon.profile, by: amount, on: .player)
        return .recharged(item: weapon.profile.item, gem: gem.item, charge: charge)
    }

    /// Soul Squeezer adds to every soul through entry point 49.
    private func gemRechargeAmount(_ soul: SoulLevel, for item: FormID) -> Float {
        let subject = coordinator.world.inventory?.baselines.items.conditionSubject(of: item)
        return coordinator.world.perkModified(
            SoulTrap.charge(of: soul), at: .modSoulGemRecharge, on: .player,
            subjects: PerkEvaluationSubjects(owner: .player).binding(.item, to: subject),
            seams: ConditionContext()
        )
    }
}

struct RechargeableWeapon {
    let profile: ItemEnchantmentProfile
    let charge: EnchantmentCharge
}
