// What a landed projectile does, by payload (issue #471, roadmap item 19.8).
//
// A satellite of `ProjectileRuntime` for the reason `ProjectileRuntimeBounds`
// is one: the class is at its strict-lint body-length cap, and generalizing the
// shot model added a second thing an impact can mean. Splitting on payload
// rather than on line count also puts the two halves side by side, which is
// where a reader comparing "an arrow does this, a spell does that" wants them.
//
// Both are internal rather than private so this file can reach them; nothing
// outside the two files calls either, because `resolve(_:impact:)` in
// `ProjectileRuntime.swift` is the only caller.
//
// Documented in docs/engine/archery.md and docs/engine/magic.md.

import Foundation
import simd

extension ProjectileRuntime {
    /// One landed arrow's health damage, or zero for anything else.
    func applyArrow(_ projectile: LiveProjectile, impact: ProjectileImpact) -> Float {
        guard
            let arrow = projectile.payload.arrow,
            let target = impact.target, let world,
            world.applyProjectileDamage(arrow.damage.applied, to: target)
        else { return 0 }
        // After the damage, for the reason the melee path reports after its
        // own (issue #375). `akProjectile` is filled in because this runtime
        // knows which PROJ struck; the wiki records vanilla leaving it `None`
        // for an actor target, which a handler that checks for `None` first
        // still tolerates.
        world.reportScriptHit(ScriptHitEvent(
            target: target,
            aggressor: projectile.shooter,
            source: arrow.weapon,
            projectile: projectile.profile.projectile
        ))
        // Archery levels on "Base Weapon Damage of the Bow"
        // (<https://en.uesp.net/wiki/Skyrim:Leveling>) — the WEAP number alone,
        // so neither the draw fraction nor the arrow raises it — and the actor
        // it struck takes the armour half of the same exchange a swing reports
        // (issue #498).
        world.reportSkillUse(SkillUseEvent(
            actor: projectile.shooter,
            action: .weaponHit(.bow),
            amount: arrow.damage.bowDamage
        ))
        world.reportSkillUse(SkillUseEvent(
            actor: target, action: .armorHit, amount: arrow.damage.applied
        ))
        applyBowEnchantment(arrow, projectile: projectile, impact: impact, world: world)
        return arrow.damage.applied
    }

    /// Fires the bow's enchantment on the actor an arrow struck (issue #472).
    ///
    /// Only a contact enchantment fires, exactly as for a swing: an enchanted bow
    /// carries the same `Contact` delivery an enchanted blade does, and a staff is
    /// not shot. An arrow that struck geometry rather than an actor applies
    /// nothing and spends nothing, which is the one place this differs from a
    /// swing — a swing only reaches this path having found a target.
    ///
    /// - Returns: what the enchantment did, discardable because the arrow's damage
    ///   is what `resolve(_:impact:)` reports and the enchantment's own outcome is
    ///   read off the session's readout instead.
    @discardableResult
    func applyBowEnchantment(
        _ arrow: ArrowPayload,
        projectile: LiveProjectile,
        impact: ProjectileImpact,
        world: any ProjectileWorld
    ) -> WeaponEnchantmentReport? {
        guard
            let profile = arrow.enchantment, profile.isContact,
            let target = impact.target
        else { return nil }
        return world.applyWeaponEnchantment(WeaponEnchantmentHit(
            profile: profile,
            attacker: projectile.shooter,
            target: target,
            position: impact.position
        ))
    }

    /// One landed spell's effect list, applied to whatever it reached.
    ///
    /// A spell that struck geometry rather than an actor still applies: its
    /// area entries reach whoever was standing near the wall. One that reaches
    /// nobody reports nil, which is what an area of zero against a wall is.
    func applySpell(
        _ projectile: LiveProjectile,
        impact: ProjectileImpact
    ) -> SpellHitReport? {
        guard let payload = projectile.payload.spell, let world else { return nil }
        let targets = SpellHitTargeting.targets(
            of: payload,
            at: impact.position,
            struck: impact.target,
            candidates: world.projectileTargets(),
            excluding: projectile.shooter,
            settings: areaSettings
        )
        guard !targets.isEmpty else { return nil }
        if let struck = impact.target {
            // `akSource` is left nil rather than filled with the spell: the
            // event carries a `FormID` and a cast spell is addressed by
            // `ReferenceKey`, which is a load-order identity a raw FormID
            // cannot round-trip. The PROJ is named, which is what tells a
            // handler this was a spell rather than a blade.
            world.reportScriptHit(ScriptHitEvent(
                target: struck,
                aggressor: projectile.shooter,
                source: nil,
                projectile: projectile.profile.projectile
            ))
        }
        return world.applySpellHit(SpellHit(
            payload: payload, position: impact.position, targets: targets
        ))
    }
}
