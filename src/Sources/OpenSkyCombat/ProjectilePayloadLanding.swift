// What a landed projectile does, by payload: an arrow's damage, riders, and skill uses,
// a spell's effect list, the impact chain, the push on a loose body, and the explosion.
// See docs/engine/projectiles.md, docs/engine/spell-delivery.md, and
// docs/formats/explosions.md.

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

/// Part of `ProjectileRuntime`: one landed projectile's effects on the world.
@MainActor
struct ProjectilePayloadLanding {
    /// Nil in a session without one: the push and the explosion still happen.
    let world: (any ProjectileWorld)?
    let areaSettings: MagicAreaSettings
    let impacts: MeleeImpactResolver?
    let explosions: ExplosionRuntime?

    /// What the runtime records of one landing.
    struct Report {
        let appliedDamage: Float
        let spellHit: SpellHitReport?
        /// An arrow that struck an actor, which may keep it.
        let keptArrow: (arrow: ArrowPayload, target: ReferenceKey)?
    }

    func land(_ projectile: LiveProjectile, impact: ProjectileImpact) -> Report {
        let arrow = applyArrow(projectile, impact: impact)
        let spellHit = applySpell(projectile, impact: impact)
        playImpact(of: impact, payload: projectile.payload)
        pushStruckBody(projectile, impact: impact)
        detonateExplosion(of: projectile, at: impact.position, source: impact.reference)
        return Report(appliedDamage: arrow.damage, spellHit: spellHit, keptArrow: arrow.kept)
    }

    // MARK: - Private

    /// One landed arrow's health damage, or zero for anything else.
    private func applyArrow(
        _ projectile: LiveProjectile, impact: ProjectileImpact
    ) -> (damage: Float, kept: (ArrowPayload, ReferenceKey)?) {
        guard let arrow = projectile.payload.arrow, let target = impact.target, let world
        else { return (0, nil) }
        // Read before the damage: the hit itself makes the target aware.
        let sneak = world.projectileIsSneakAttack(by: projectile.shooter, on: target)
        guard world.applyProjectileDamage(
            arrow.damage.applied, to: target, from: projectile.shooter
        ) else { return (0, nil) }
        // After the damage, as the melee path does. `akProjectile` is filled in; vanilla
        // leaves it `None` for an actor target, which handlers already tolerate.
        world.reportScriptHit(ScriptHitEvent(
            target: target,
            aggressor: projectile.shooter,
            source: arrow.weapon,
            projectile: projectile.profile.projectile,
            isSneakAttack: sneak,
            damage: arrow.damage.applied
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
        world.applyWeaponPoison(WeaponPoisonHit(
            attacker: projectile.shooter, weapon: arrow.weapon, target: target
        ))
        return (arrow.damage.applied, (arrow, target))
    }

    /// Fires the bow's enchantment where an arrow struck an actor. Only a contact
    /// enchantment fires. An arrow that hit geometry applies and spends nothing.
    private func applyBowEnchantment(
        _ arrow: ArrowPayload,
        projectile: LiveProjectile,
        impact: ProjectileImpact,
        world: any ProjectileWorld
    ) {
        guard
            let profile = arrow.enchantment, profile.isContact,
            let target = impact.target
        else { return }
        _ = world.applyWeaponEnchantment(WeaponEnchantmentHit(
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
    private func applySpell(
        _ projectile: LiveProjectile,
        impact: ProjectileImpact
    ) -> SpellHitReport? {
        guard let payload = projectile.payload.spell, let world else { return nil }
        let targets = SpellHitTargeting.targets(
            of: payload,
            landing: (impact.position, impact.target),
            candidates: world.projectileTargets(),
            excluding: projectile.shooter,
            settings: areaSettings
        )
        guard !targets.isEmpty else {
            world.spellLanded(payload, at: impact.position)
            return nil
        }
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
            payload: payload, targets: targets, impact: impact.position
        ))
    }

    /// The IPCT chain for a hit, played where the world can play it.
    private func playImpact(of impact: ProjectileImpact, payload: ProjectilePayload) {
        guard let world, let impacts else { return }
        // A spell shows its MGEF impact data set. An arrow resolves through the
        // ammunition's chain; AMMO has no INAM, so it carries the unarmed profile's
        // nil data set.
        let material = impact.material ?? impact.target.flatMap { world.impactMaterial(of: $0) }
        let spellImpact = payload.spell?.impactDataSet.flatMap {
            impacts.resolve(dataSet: $0, material: material)
        }
        guard var resolved = spellImpact ?? impacts.resolve(weapon: .unarmed, material: material)
        else {
            if let target = impact.target {
                world.showDefaultBlood(on: target, at: impact.position, melee: false)
            }
            return
        }
        resolved.target = impact.target
        resolved.surfaceNormal = impact.normal
        world.playProjectileImpact(resolved, at: impact.position)
    }

    /// Sets off the projectile's explosion at `position`. A spell's projectile is a spell
    /// cause; anything else is a projectile cause.
    private func detonateExplosion(
        of projectile: LiveProjectile,
        at position: SIMD3<Float>,
        source: FormID?
    ) {
        guard
            let explosions,
            let spec = explosions.spec(itemLink: projectile.profile.explosion)
        else { return }
        _ = explosions.detonate(
            spec, at: position, cause: projectile.payload.spell == nil ? .projectile : .spell,
            source: source
        )
    }

    /// Pushes the loose body a projectile struck by its `PROJ` impact force, along its flight.
    private func pushStruckBody(_ projectile: LiveProjectile, impact: ProjectileImpact) {
        guard
            !impact.isActor, let reference = impact.reference,
            let impulses = explosions?.impulses, let world = impulses.world,
            let body = world.impulseBodies().first(where: { $0.reference == reference }),
            let push = GameplayImpulse.projectile(
                impactForce: projectile.profile.impactForce,
                impact: (projectile.state.velocity, impact.position), body: body,
                settings: impulses.settings
            )
        else { return }
        world.applyBodyImpulse(push)
        impulses.record(.push(body.key, impulse: simd_length(push.linear), cause: .projectile))
    }
}
