// What one landed swing does beyond its damage number: the block stamina, the skill
// uses, the hit spell, poison and enchantment, the script event, the stagger, and the
// impact. See docs/engine/melee-combat.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import simd

/// Part of `MeleeCombatRuntime`: one blow's effects on its target, in a fixed order.
@MainActor
struct MeleeBlowLanding {
    let world: any MeleeCombatWorld
    let weapon: MeleeWeaponProfile
    let kind: MeleeStrikeKind
    let skillUses: MeleeSkillUseSettings
    let staggers: StaggerSettings
    let impacts: MeleeImpactResolver?

    /// Returns whether the target staggered. `random` is drawn from only for the
    /// `iStaggerAttackChance` roll.
    func land(
        _ hit: MeleeHit, damage: MeleeDamageResult, random: inout ConditionRandom
    ) -> Bool {
        let landed = world.applyMeleeDamage(damage.applied, to: hit.target)
        if damage.wasBlocked {
            world.applyBlockStamina(damage, to: hit.target)
        }
        noteSkillUse(hit, damage: damage, landed: landed)
        if landed {
            world.applyMeleeHitSpell(blow, on: hit.target)
            applyWeaponRiders(on: hit.target)
        }
        applyEnchantment(hit)
        // After the damage, so an `OnHit` script sees the new health. `abHitBlocked`
        // comes from the damage formula's block term.
        world.reportScriptHit(ScriptHitEvent(
            target: hit.target,
            aggressor: world.meleeAttacker.key,
            source: weapon.weapon,
            isPowerAttack: kind.isPowerAttack,
            isSneakAttack: damage.strike.isSneakAttack,
            isBashAttack: kind.isBash,
            isBlocked: damage.wasBlocked,
            damage: landed ? damage.applied : 0
        ))
        let staggered = stagger(hit.target, damage: damage, random: &random)
        // A swing only strikes actors; the race's impact material picks the entry.
        var impact = impacts?.resolve(
            weapon: weapon, material: world.impactMaterial(of: hit.target)
        )
        impact?.target = hit.target
        if let impact {
            world.playMeleeImpact(impact, at: hit.position)
        } else {
            world.showDefaultBlood(on: hit.target, at: hit.position, melee: true)
        }
        return staggered
    }

    // MARK: - Private

    /// The swing, as the perk terms read it.
    private var blow: CombatBlow {
        CombatBlow(
            attacker: world.meleeAttacker.key,
            weapon: weapon.weapon,
            handType: weapon.handType,
            kind: kind,
            baseDamage: weapon.damage
        )
    }

    /// Reports what this blow taught both characters (`MeleeSkillUses`).
    private func noteSkillUse(_ hit: MeleeHit, damage: MeleeDamageResult, landed: Bool) {
        let blow = MeleeSkillUseBlow(
            attacker: world.meleeAttacker.key,
            target: hit.target,
            handType: weapon.handType,
            kind: kind,
            damage: damage,
            landed: landed,
            bashedWithShield: kind.isBash && world.meleeBashSource().shieldRating != nil,
            weapon: world.meleeResolvedWeapon(weapon.weapon)
        )
        for use in MeleeSkillUses.events(for: blow, settings: skillUses) {
            world.reportSkillUse(use)
        }
    }

    /// Fires the weapon's enchantment at the contact point. Only a contact
    /// enchantment fires. The world seam owns the charge, so a dry weapon returns a
    /// report that says so.
    private func applyEnchantment(_ hit: MeleeHit) {
        guard let profile = weapon.enchantment, profile.isContact else { return }
        _ = world.applyWeaponEnchantment(WeaponEnchantmentHit(
            profile: profile,
            attacker: world.meleeAttacker.key,
            struck: hit.target,
            at: hit.position,
            candidates: world.meleeTargets()
        ))
    }

    /// A landed hit carries the weapon's poison and any Enhance Weapon enchantment.
    private func applyWeaponRiders(on target: ReferenceKey) {
        world.applyWeaponPoison(WeaponPoisonHit(
            attacker: world.meleeAttacker.key, weapon: weapon.weapon, target: target
        ))
        if weapon.weapon != nil {
            world.applyWeaponEnhancement(attacker: world.meleeAttacker.key, target: target)
        }
    }

    /// Tells the target's graph to stagger when the hit's magnitude passes `fStaggerMin`
    /// and the `iStaggerAttackChance` roll passes.
    ///
    /// `staggerMagnitude` is written before the event so the stagger behavior reads
    /// this hit's magnitude rather than the previous one's.
    private func stagger(
        _ target: ReferenceKey, damage: MeleeDamageResult, random: inout ConditionRandom
    ) -> Bool {
        guard damage.applied > 0 else { return false }
        let magnitude = StaggerRule.magnitude(
            staggerHit(damage: damage), settings: staggers
        )
        let roll = random.percent()
        guard StaggerRule.staggers(magnitude: magnitude, roll: roll, settings: staggers)
        else { return false }
        world.writeCombatVariable(
            .real(magnitude), named: CombatGraphNames.staggerMagnitude, on: target
        )
        return world.raiseCombatEvent(CombatGraphNames.staggerStart, on: target)
    }

    private func staggerHit(damage: MeleeDamageResult) -> StaggerHit {
        var hit = StaggerHit(weaponStagger: weapon.stagger)
        hit.perkMultiplier = damage.strike.staggerMultiplier
        hit.wasBlocked = damage.wasBlocked
        hit.isPowerBash = kind == .powerBash
        if kind.isBash {
            let source = world.meleeBashSource()
            hit.kind = .bash(shieldRating: source.shieldRating)
            hit.attackerBlockSkill = source.blockSkill
        } else {
            hit.kind = kind == .power ? .power : .swing
        }
        return hit
    }
}
