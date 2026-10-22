// The perk entry points of a weapon hit: damage, critical hits, stagger, sweeps,
// arrow deflection, and the spells a hit or a swing applies. The subjects each
// condition tab names, and the sources: docs/engine/perks.md.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension CombatCoordinator {
    /// `key`'s perks at `entryPoint` applied to `value`. Without a world, `value`.
    func perkValue(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects
    ) -> Float {
        world.perkModified(
            value, at: entryPoint, on: key, subjects: subjects, seams: ConditionContext()
        )
    }

    /// The attacker owns the perk; the weapon and the target are bound.
    func attackSubjects(_ blow: CombatBlow, on target: ReferenceKey) -> PerkEvaluationSubjects {
        PerkEvaluationSubjects(owner: blow.attacker, target: target)
            .binding(.weapon, to: items?.conditionSubject(of: blow.weapon))
    }

    /// The struck actor owns the perk; the attacker and its weapon are bound.
    func defenceSubjects(_ blow: CombatBlow, on target: ReferenceKey) -> PerkEvaluationSubjects {
        PerkEvaluationSubjects(owner: target, attacker: blow.attacker)
            .binding(.attackerWeapon, to: items?.conditionSubject(of: blow.weapon))
    }

    /// The perk terms of `blow`. A bash takes neither the attack-damage perks nor a
    /// critical, as it takes no fortify term.
    func applyPerkTerms(to strike: inout WeaponStrike, blow: CombatBlow, on target: ReferenceKey) {
        let attack = attackSubjects(blow, on: target)
        let owner = PerkEvaluationSubjects(owner: blow.attacker, target: target)
        if blow.kind.isBash {
            strike.bashMultiplier = perkValue(
                1, at: .modBashingDamage, on: blow.attacker, subjects: owner
            )
        } else {
            let damage = perkValue(
                blow.baseDamage, at: .calculateWeaponDamage, on: blow.attacker, subjects: attack
            )
            strike.weaponDamageBonus = damage - blow.baseDamage
            strike.perkMultiplier = perkValue(
                1, at: .modAttackDamage, on: blow.attacker, subjects: attack
            )
            rollCritical(into: &strike, blow: blow, subjects: attack)
        }
        if blow.kind == .power {
            strike.powerMultiplier = perkValue(
                1, at: .modPowerAttackDamage, on: blow.attacker, subjects: attack
            )
        }
        strike.perkMultiplier *= perkValue(
            1, at: .modIncomingDamage, on: target, subjects: defenceSubjects(blow, on: target)
        )
        strike.staggerMultiplier = perkValue(
            1, at: .modTargetStagger, on: blow.attacker, subjects: owner
        ) * perkValue(
            1,
            at: .modIncomingStagger,
            on: target,
            subjects: PerkEvaluationSubjects(owner: target, attacker: blow.attacker)
        )
    }

    /// CK wiki "Perk Entry Point": the chance starts at 0 without perks, and `CRDT`
    /// scales it. The critical damage starts at the weapon's `CRDT` damage.
    private func rollCritical(
        into strike: inout WeaponStrike, blow: CombatBlow, subjects: PerkEvaluationSubjects
    ) {
        let critical = blow.weapon.flatMap { items?.weapon($0)?.criticalData }
        let base = ActorValueIdentity.index(named: "Critical Chance")
            .flatMap { world.actorValues(of: blow.attacker)?($0) } ?? 0
        let chance = perkValue(
            base, at: .calculateCriticalChance, on: blow.attacker, subjects: subjects
        ) * (critical?.percentMultiplier ?? 1)
        guard chance > 0, Float(strikeRandom.percent()) < chance else { return }
        strike.isCritical = true
        strike.criticalDamage = perkValue(
            Float(critical?.damage ?? 0),
            at: .calculateCriticalDamage,
            on: blow.attacker,
            subjects: subjects
        )
    }

    /// The spell of the attacker's first passing `Apply Combat Hit Spell` effect, or
    /// `Apply Bashing Spell` for a bash, lands on the target. An unarmed hit is not a
    /// combat hit (CK wiki "Perk Entry Point").
    @discardableResult
    public func applyPerkHitSpell(_ blow: CombatBlow, on target: ReferenceKey) -> SpellHitReport? {
        let entryPoint: PerkEntryPoint
        let subjects: PerkEvaluationSubjects
        if blow.kind.isBash {
            entryPoint = .applyBashingSpell
            subjects = PerkEvaluationSubjects(owner: blow.attacker, target: target)
        } else {
            guard blow.weapon != nil else { return nil }
            entryPoint = .applyCombatHitSpell
            subjects = attackSubjects(blow, on: target)
        }
        let disarmChance = blow.kind.isBash
            ? staggers.blockDisarmChance : staggers.attackDisarmChance
        return applyChosenSpell(
            at: entryPoint, owner: blow.attacker, subjects: subjects, caster: blow.attacker,
            on: target, disarmChance: disarmChance
        )
    }

    /// `Apply Weapon Swing Spell`: an enemy's swing at `target` lands the spell of
    /// `target`'s own perk on `target`, before the swing makes contact.
    @discardableResult
    public func applyPerkSwingSpell(
        _ blow: CombatBlow,
        at target: ReferenceKey
    ) -> SpellHitReport? {
        applyChosenSpell(
            at: .applyWeaponSwingSpell,
            owner: target,
            subjects: defenceSubjects(blow, on: target),
            caster: target,
            on: target
        )
    }

    /// `Apply Sneaking Spell`: entering sneak casts the chosen spell on the player,
    /// as Shadow Warrior's invisibility in combat.
    @discardableResult
    public func notePlayerSneaking(_ isSneaking: Bool) -> SpellHitReport? {
        defer { wasPlayerSneaking = isSneaking }
        guard isSneaking, !wasPlayerSneaking else { return nil }
        return applyChosenSpell(
            at: .applySneakingSpell,
            owner: .player,
            subjects: PerkEvaluationSubjects(owner: .player),
            caster: .player,
            on: .player
        )
    }

    /// `Set Boolean Graph Variable`: the player's graph flags that changed since the
    /// last frame. A perk that stops passing, as Ranger when sneaking, clears its flag.
    public func perkGraphFlagChanges() -> [String: Bool] {
        let now = Set(world.perkChoices(
            at: .setBooleanGraphVariable,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player),
            seams: ConditionContext()
        ).compactMap(\.inlineText))
        defer { perkGraphFlags = now }
        var changes: [String: Bool] = [:]
        for name in now.subtracting(perkGraphFlags) {
            changes[name] = true
        }
        for name in perkGraphFlags.subtracting(now) {
            changes[name] = false
        }
        return changes
    }

    /// `Set Sweep Attack`: a swing that sweeps strikes every actor in its arc.
    public func perkSweeps(_ blow: CombatBlow) -> Bool {
        perkValue(
            0,
            at: .setSweepAttack,
            on: blow.attacker,
            subjects: PerkEvaluationSubjects(owner: blow.attacker)
                .binding(.weapon, to: items?.conditionSubject(of: blow.weapon))
        ) != 0
    }

    /// `Mod Shield Deflect Arrow Chance`, rolled when an arrow strikes an actor with a
    /// shield. The chance is capped at 100. The vanilla perk's own condition asks for a block.
    func deflectsArrow(_ target: ReferenceKey) -> Bool {
        guard let items else { return false }
        let hasShield = world.equippedItems(of: target).contains { worn in
            items.armor[worn.item.rawValue]?.bodyTemplate?.slots.contains(.shield) ?? false
        }
        guard hasShield else { return false }
        let chance = min(100, perkValue(
            0,
            at: .modShieldDeflectArrowChance,
            on: target,
            subjects: PerkEvaluationSubjects(owner: target)
        ))
        return chance > 0 && Float(strikeRandom.percent()) < chance
    }

    private func applyChosenSpell(
        at entryPoint: PerkEntryPoint,
        owner: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        caster: ReferenceKey,
        on target: ReferenceKey,
        disarmChance: Int = 100
    ) -> SpellHitReport? {
        guard
            let spell = world.perkChoices(
                at: entryPoint, on: owner, subjects: subjects, seams: ConditionContext()
            ).lazy.compactMap(\.spell).first
        else { return nil }
        // `iPerkAttackDisarmChance` and `iPerkBlockDisarmChance` gate a disarm spell.
        let disarms = spell.effects.contains { $0.effect?.effect.data?.archetype == .disarm }
        if disarms, strikeRandom.percent() >= disarmChance { return nil }
        return world.applySpellHit(SpellHit(
            payload: spell.payload(caster: caster), targets: [SpellHitTarget(key: target)]
        ))
    }
}
