// Putting charge back into an enchanted weapon: a soul gem the player spends, or Soul
// Siphon's share of a creature's soul at a killing blow. The charge goes on the
// weapon's best copy. See docs/engine/item-enchantments.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// What one recharge did.
nonisolated public enum RechargeOutcome: Equatable, Sendable {
    case recharged(item: FormID, gem: FormID, charge: EnchantmentCharge)
    /// The player has no equipped enchanted weapon that is short of charge.
    case nothingToRecharge
    case noFilledGem
    case unavailable
}

extension MagicCoordinator {
    /// Recharges the player's equipped weapon from the smallest filled gem that fills
    /// it, or the largest gem when none does.
    @discardableResult
    public func rechargeEquippedWeapon() -> RechargeOutcome {
        guard let runtime = effects, let inventory = world.inventory else {
            return .unavailable
        }
        guard let weapon = rechargeableWeapon(on: .player, staves: true) else {
            return .nothingToRecharge
        }
        let missing = weapon.charge.capacity - weapon.charge.remaining
        let worth = { (gem: SoulGemCandidate) in
            self.gemRechargeAmount(gem.soul, for: weapon.profile.item)
        }
        let filled = carriedGems(inventory).filter { $0.soul != .empty }
        let fitting = filled.filter { worth($0) >= missing }
        guard
            let gem = fitting.min(by: { worth($0) < worth($1) })
            ?? filled.max(by: { worth($0) < worth($1) })
        else { return .noFilledGem }
        let amount = worth(gem)
        spendGem(gem, in: inventory)
        reportEnchantingUse(EnchantingRules.rechargeExperience(gem.soul))
        let charge = EnchantmentLedger(store: runtime.store, inventory: inventory)
            .recharge(weapon.profile, by: amount, on: .player)
        return .recharged(item: weapon.profile.item, gem: gem.item, charge: charge)
    }

    /// Soul Siphon: entry point 78 gives the share of `victim`'s soul that goes into
    /// the killer's weapon. The perk's own condition leaves people out.
    @discardableResult
    func siphonSoul(of victim: ActorValueHolder, killer: ReferenceKey) -> EnchantmentCharge? {
        guard
            let runtime = effects,
            let items = world.inventory?.baselines.items,
            let owner = world.actorValueHolder(for: killer),
            let weapon = rechargeableWeapon(on: owner, staves: false)
        else { return nil }
        let share = world.perkModified(
            0, at: .modSoulPctCapturedToWeapon, on: killer,
            subjects: PerkEvaluationSubjects(owner: killer, target: victim.key)
                .binding(.item, to: items.conditionSubject(of: weapon.profile.item)),
            seams: ConditionContext()
        )
        guard share > 0 else { return nil }
        let soul = SoulTrap.soul(
            level: runtime.values.baseline(of: victim).level,
            isNPC: world.actorHasKeyword("ActorTypeNPC", on: victim),
            settings: soulTrapSettings
        )
        return EnchantmentLedger(store: runtime.store, inventory: world.inventory)
            .recharge(weapon.profile, by: SoulTrap.charge(of: soul.size) * share, on: owner)
    }

    /// Soul Squeezer adds to every soul through entry point 49.
    private func gemRechargeAmount(_ soul: SoulLevel, for item: FormID) -> Float {
        let subject = world.inventory?.baselines.items.conditionSubject(of: item)
        return world.perkModified(
            SoulTrap.charge(of: soul), at: .modSoulGemRecharge, on: .player,
            subjects: PerkEvaluationSubjects(owner: .player).binding(.item, to: subject),
            seams: ConditionContext()
        )
    }

    /// The first equipped weapon with a metered charge below full.
    private func rechargeableWeapon(on holder: ActorValueHolder, staves: Bool)
        -> RechargeableWeapon?
    {
        guard let runtime = effects, let equipment = world.equipment else { return nil }
        let ledger = EnchantmentLedger(store: runtime.store, inventory: world.inventory)
        return equipment.equipped(on: InventoryHolder(actor: holder)).lazy
            .compactMap { self.enchantmentProfile(of: $0, on: InventoryHolder(actor: holder)) }
            .filter { !$0.isWorn && (staves || !$0.isStaff) }
            .map { RechargeableWeapon(profile: $0, charge: ledger.charge(of: $0, on: holder)) }
            .first { $0.charge.isMetered && $0.charge.remaining < $0.charge.capacity }
    }

    /// A reusable gem, such as Azura's Star, empties and stays; any other gem is used up.
    func spendGem(_ gem: SoulGemCandidate, in inventory: any InventoryAccess) {
        if gem.copy.soul != 0 {
            inventory.editCopy(
                of: gem.item,
                in: .player,
                where: { $0 == gem.copy },
                { $0.soul = 0 }
            )
        }
        guard !world.itemHasKeyword("ReusableSoulGem", on: gem.item) else { return }
        _ = try? inventory.remove(gem.item, count: 1, from: .player)
    }
}

private struct RechargeableWeapon {
    let profile: ItemEnchantmentProfile
    let charge: EnchantmentCharge
}
