// One NPC blow, landed through the player's own hit path: the pinned 15.4 damage
// formula, the health write, the hit spell, the script event, and, on the player, the
// skill uses, the block recoil, and the hit reaction. See docs/engine/combat-behavior.md.

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

/// Part of `CombatLoopRuntime`: what one NPC blow does to its target.
@MainActor
struct CombatNPCBlowLanding {
    let world: any CombatLoopWorld
    let settings: CombatSettings
    let skillUses: MeleeSkillUseSettings
    let staggers: StaggerSettings

    /// What a blow on the player leaves for the runtime to note.
    struct PlayerReaction {
        let hit: CombatIncomingHit
        /// The player blocked, and the attacker recoils.
        let recoils: Bool
    }

    /// The damage the blow would apply, without landing it.
    func appliedDamage(
        by actor: ReferenceKey, weapon: MeleeWeaponProfile, on target: ReferenceKey
    ) -> Float {
        damage(of: Self.blow(by: actor, weapon: weapon), weapon: weapon, on: target).applied
    }

    /// Nil unless the target is the player. `random` is drawn from only for the
    /// recoil and stagger rolls.
    func land(
        from actor: ReferenceKey, weapon: MeleeWeaponProfile, to target: ReferenceKey,
        random: inout ConditionRandom
    ) -> PlayerReaction? {
        let blow = Self.blow(by: actor, weapon: weapon)
        let damage = damage(of: blow, weapon: weapon, on: target)
        let landed = world.applyCombatBlow(damage.applied, to: target, blow: blow)
        if landed {
            world.applyCombatHitSpell(blow, on: target)
        }
        if damage.wasBlocked {
            world.applyCombatBlockStamina(damage, to: target)
        }
        // The reverse of the player's own swing dispatch: the target's scripts get
        // `OnHit` with this actor as `akAggressor`.
        world.reportScriptHit(ScriptHitEvent(
            target: target,
            aggressor: actor,
            source: weapon.weapon,
            isBlocked: damage.wasBlocked,
            damage: landed ? damage.applied : 0
        ))
        guard target == world.combatPlayer.key else { return nil }
        noteSkillUse(from: actor, weapon: weapon, result: (damage, landed))
        let recoils = damage.wasBlocked && rollsBlockRecoil(blockedBy: target, random: &random)
        // The magnitude is written before the event so the recoil behavior
        // reads this blow's number rather than the previous one's, which is the
        // same write-then-raise order the melee runtime uses for a stagger.
        let played = damage.applied > 0
            && (raiseStagger(weapon: weapon, damage: damage, random: &random)
                || raiseRecoil(magnitude: damage.applied))
        return PlayerReaction(
            hit: CombatIncomingHit(damage: damage, playedReaction: played),
            recoils: recoils
        )
    }

    static func blow(by actor: ReferenceKey, weapon: MeleeWeaponProfile) -> CombatBlow {
        CombatBlow(
            attacker: actor,
            weapon: weapon.weapon,
            handType: weapon.handType,
            baseDamage: weapon.damage
        )
    }

    // MARK: - Private

    private func damage(
        of blow: CombatBlow, weapon: MeleeWeaponProfile, on target: ReferenceKey
    ) -> MeleeDamageResult {
        MeleeDamage.resolve(
            weapon: weapon,
            block: world.combatBlock(of: target),
            settings: settings,
            blockSkill: world.combatBlockSkill(of: target),
            bonusMultiplier: world.combatBlockMultiplier(of: target),
            strike: world.combatStrike(blow, on: target)
        )
    }

    /// The reverse of the player's own swing report. NPC blows are plain swings, and
    /// progression decides who advances (the player only).
    private func noteSkillUse(
        from actor: ReferenceKey,
        weapon: MeleeWeaponProfile,
        result: (damage: MeleeDamageResult, landed: Bool)
    ) {
        let (damage, landed) = result
        let blow = MeleeSkillUseBlow(
            attacker: actor,
            target: world.combatPlayer.key,
            handType: weapon.handType,
            damage: damage,
            landed: landed
        )
        for use in MeleeSkillUses.events(for: blow, settings: skillUses) {
            world.reportSkillUse(use)
        }
    }

    /// An NPC blow staggers the player by `StaggerRule`, the player's mass included.
    /// Returns whether the graph declared the event, which is the graph's own answer.
    private func raiseStagger(
        weapon: MeleeWeaponProfile, damage: MeleeDamageResult, random: inout ConditionRandom
    ) -> Bool {
        var hit = StaggerHit(weaponStagger: weapon.stagger)
        hit.perkMultiplier = damage.strike.staggerMultiplier
        hit.wasBlocked = damage.wasBlocked
        hit.isPlayerTarget = true
        let magnitude = StaggerRule.magnitude(hit, settings: staggers)
        let roll = random.percent()
        guard StaggerRule.staggers(magnitude: magnitude, roll: roll, settings: staggers)
        else { return false }
        world.writeCombatVariable(.real(magnitude), named: CombatGraphNames.staggerMagnitude)
        return world.raiseCombatEvent(CombatGraphNames.staggerStart, on: nil)
    }

    /// A swing the player blocked recoils its attacker by the player's Block skill.
    private func rollsBlockRecoil(
        blockedBy blocker: ReferenceKey, random: inout ConditionRandom
    ) -> Bool {
        let magnitude = StaggerRule.blockRecoil(
            blockerSkill: world.combatBlockSkill(of: blocker), settings: staggers
        )
        let roll = random.percent()
        return StaggerRule.staggers(magnitude: magnitude, roll: roll, settings: staggers)
    }

    private func raiseRecoil(magnitude: Float) -> Bool {
        world.writeCombatVariable(.real(magnitude), named: CombatGraphNames.recoilMagnitude)
        return world.raiseCombatEvent(CombatGraphNames.recoilStart, on: nil)
    }
}
