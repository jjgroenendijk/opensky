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
    /// The bash damage ranges.
    var powerAttacks = PowerAttackSettings.vanilla

    /// What a blow on the player leaves for the runtime to note.
    struct PlayerReaction {
        let hit: CombatIncomingHit
        /// The player blocked, and the attacker recoils.
        let recoils: Bool
    }

    /// The damage the blow would apply, without landing it.
    func appliedDamage(
        by actor: ReferenceKey, weapon: MeleeWeaponProfile, on target: ReferenceKey,
        attack: NPCAttack? = nil
    ) -> Float {
        damage(
            of: Self.blow(by: actor, weapon: weapon, attack: attack), weapon: weapon, on: target
        ).applied
    }

    /// Nil unless the target is the player. `random` is drawn from only for the
    /// recoil and stagger rolls.
    func land(
        from actor: (key: ReferenceKey, feet: SIMD3<Float>),
        weapon strike: (profile: MeleeWeaponProfile, attack: NPCAttack?),
        to target: ReferenceKey, random: inout ConditionRandom
    ) -> PlayerReaction? {
        let (actor, feet) = actor
        let (weapon, attack) = strike
        let blow = Self.blow(by: actor, weapon: weapon, attack: attack)
        let damage = damage(of: blow, weapon: weapon, on: target)
        let landed = world.applyCombatBlow(damage.applied, to: target, blow: blow)
        if landed {
            world.applyCombatHitSpell(blow, on: target)
            passDisease(from: actor, to: target, random: &random)
            if
                let knockdown = attack?.data.knockdown, knockdown > 0,
                world.combatHealth(of: target) > 0
            {
                world.knockDownCombatTarget(
                    target, from: feet, magnitude: knockdown,
                    staggerMult: damage.strike.staggerMultiplier
                )
            }
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
            isPowerAttack: attack?.isPowerAttack ?? false,
            isBlocked: damage.wasBlocked,
            damage: landed ? damage.applied : 0
        ))
        guard target == world.combatPlayer.key else { return nil }
        noteSkillUse(from: actor, weapon: weapon, result: (damage, landed))
        var hit = HitReactionHit()
        hit.facts = world.combatHitFacts(
            from: actor, on: target, event: blow.attackEvent ?? CombatGraphNames.attackStart,
            weaponStagger: weapon.stagger
        )
        hit.handType = weapon.handType
        hit.wasBlocked = damage.wasBlocked
        hit.isPlayerTarget = true
        hit.perkMultiplier = damage.strike.staggerMultiplier
        let reaction = HitReactionRule.reaction(hit, roll: random.percent(), settings: staggers)
        world.noteCombatHitReaction(HitReactionReport(
            attacker: actor, target: target, hit: hit, reaction: reaction
        ))
        var played = false
        if reaction.blockHit {
            played = world.raiseCombatEvent(CombatGraphNames.blockHitStart, on: nil)
        }
        if let magnitude = reaction.staggerMagnitude {
            played = raiseStagger(magnitude: magnitude, direction: hit.facts.direction) || played
        }
        return PlayerReaction(
            hit: CombatIncomingHit(damage: damage, playedReaction: played),
            recoils: reaction.attackerRecoils
        )
    }

    static func blow(
        by actor: ReferenceKey, weapon: MeleeWeaponProfile, attack: NPCAttack? = nil
    ) -> CombatBlow {
        var blow = CombatBlow(
            attacker: actor,
            weapon: weapon.weapon,
            handType: weapon.handType,
            kind: kind(of: attack),
            baseDamage: weapon.damage
        )
        blow.attackEvent = attack?.event
        return blow
    }

    static func kind(of attack: NPCAttack?) -> MeleeStrikeKind {
        guard let attack else { return .normal }
        if attack.isBash {
            return attack.isPowerAttack ? .powerBash : .bash
        }
        return attack.isPowerAttack ? .power : .normal
    }

    // MARK: - Private

    /// A landed blow rolls the attacker's disease against the target's resistance. The
    /// roll is drawn only for an attacker that carries one, so other fights draw the same.
    private func passDisease(
        from actor: ReferenceKey, to target: ReferenceKey, random: inout ConditionRandom
    ) {
        guard let disease = world.combatAttackDisease(of: actor) else { return }
        let roll = random.percent()
        guard
            DiseaseContraction.contracts(resist: world.combatDiseaseResist(of: target), roll: roll)
        else { return }
        world.contractCombatDisease(disease, on: target)
    }

    private func damage(
        of blow: CombatBlow, weapon: MeleeWeaponProfile, on target: ReferenceKey
    ) -> MeleeDamageResult {
        let strike = world.combatStrike(blow, on: target)
        return MeleeDamage.resolve(
            weapon: blow.kind.isBash ? bashing(weapon, blow: blow, strike: strike) : weapon,
            block: world.combatBlock(of: target),
            settings: settings,
            blockSkill: world.combatBlockSkill(of: target),
            bonusMultiplier: world.combatBlockMultiplier(of: target),
            strike: strike
        )
    }

    /// A bash deals the bash damage of the attacker's shield, or else its weapon, instead
    /// of the weapon's own (docs/engine/combat-blocking.md#bash).
    private func bashing(
        _ weapon: MeleeWeaponProfile, blow: CombatBlow, strike: WeaponStrike
    ) -> MeleeWeaponProfile {
        let source = BashSource(
            weaponDamage: weapon.damage,
            shieldRating: world.combatShieldRating(of: blow.attacker),
            blockSkill: world.combatBlockSkill(of: blow.attacker)
        )
        return weapon.dealing(damage: strike.bashMultiplier * MeleeBash.damage(
            source, isPlayer: false, isPower: blow.kind == .powerBash, settings: powerAttacks
        ))
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

    /// The values are written before the event, so the stagger behaviour reads this
    /// blow's numbers. Returns whether the graph declared the event.
    private func raiseStagger(magnitude: Float, direction: Float) -> Bool {
        world.writeCombatVariable(.real(magnitude), named: CombatGraphNames.staggerMagnitude)
        world.writeCombatVariable(.real(direction), named: CombatGraphNames.staggerDirection)
        return world.raiseCombatEvent(CombatGraphNames.staggerStart, on: nil)
    }
}
