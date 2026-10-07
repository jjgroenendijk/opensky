// What a landed projectile does, by payload: an arrow or a spell. A satellite
// of `ProjectileRuntime`, which is at its body-length cap.
// See docs/engine/projectiles.md and docs/engine/spell-delivery.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import simd

extension ProjectileRuntime {
    /// One landed arrow's health damage, or zero for anything else.
    public func applyArrow(_ projectile: LiveProjectile, impact: ProjectileImpact) -> Float {
        guard
            let arrow = projectile.payload.arrow,
            let target = impact.target, let world,
            world.applyProjectileDamage(arrow.damage.applied, to: target)
        else { return 0 }
        // After the damage, as the melee path does. `akProjectile` is filled in; vanilla
        // leaves it `None` for an actor target, which handlers already tolerate.
        world.reportScriptHit(ScriptHitEvent(
            target: target,
            aggressor: projectile.shooter,
            source: arrow.weapon,
            projectile: projectile.profile.projectile
        ))
        // Archery levels on the bow's base WEAP damage
        // (<https://en.uesp.net/wiki/Skyrim:Leveling>), and the target takes the armor
        // half, as for a swing.
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

    /// Fires the bow's enchantment where an arrow struck an actor. Only a contact
    /// enchantment fires. An arrow that hit geometry applies and spends nothing.
    /// - Returns: what the enchantment did; discardable, because the readout shows it.
    @discardableResult
    public func applyBowEnchantment(
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
            struck: target,
            at: impact.position,
            candidates: world.projectileTargets(),
            settings: areaSettings
        ))
    }

    /// One landed spell's effect list, applied to whatever it reached.
    ///
    /// A spell that struck geometry rather than an actor still applies: its
    /// area entries reach whoever was standing near the wall. One that reaches
    /// nobody reports nil, which is what an area of zero against a wall is.
    public func applySpell(
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
            payload: payload, targets: targets
        ))
    }
}
