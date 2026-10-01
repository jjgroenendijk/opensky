// `SpellHitApplying` and the aimed-delivery answers: where a spell projectile
// leaves from, what the aim ray reaches, and how a landed spell applies. A
// projectile hit and a direct cast take one path into `ActiveEffectRuntime`.
// The aim ray uses the projectile queries but no aim assist, and PROJ lookups
// use the combat item index, so a session without one fires no spell projectile.

import AppKit
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension GameViewController: SpellHitApplying {
    /// Applies one landed spell through the same effect runtime a potion uses.
    ///
    /// The runtime is a value over a shared store, so it is taken out, worked
    /// through and put back — the pattern `consumeMagicItem` follows, and what
    /// keeps the Magic Effects panel's tally counting a spell hit too.
    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        guard var runtime = magicEffects.runtime else { return .none }
        var holders: [ReferenceKey: ActorValueHolder] = [:]
        for target in hit.targets {
            holders[target.key] = actorValueHolder(for: target.key)
        }
        let report = SpellHitApplication.apply(hit, holders: holders, using: &runtime)
        magicEffects.runtime = runtime
        magicEffects.lastHit = report
        return report
    }
}

extension GameViewController {
    /// The flight profile of the PROJ an MGEF names, or nil when this session
    /// cannot resolve one.
    func spellProjectileProfile(_ id: FormID) -> ProjectileProfile? {
        combat.items?.projectileProfile(id)
    }

    /// Launches a spell projectile through the arrow's `ProjectileRuntime`, so
    /// it shares the fixed step, bounds and impact query. It leaves the
    /// payload's own caster, so an NPC's spell leaves the NPC.
    @discardableResult
    func launchSpellProjectile(_ payload: SpellPayload) -> Bool {
        guard
            let runtime = combat.archery,
            let link = payload.projectile,
            let profile = spellProjectileProfile(link),
            let shooter = spellShooter(for: payload.caster)
        else { return false }
        return runtime.projectiles.fire(
            ProjectileShot.spell(profile: profile, payload: payload),
            from: shooter
        ) != nil
    }

    /// Where `caster` casts from and which way, or nil when it cannot be
    /// placed. The player casts down the camera ray; an NPC casts from its eye
    /// at the player, the only target `StartCombat` accepts.
    func spellShooter(for caster: ReferenceKey) -> ProjectileShooter? {
        guard caster != .player else { return combat.projectileShooter }
        guard let origin = actorCastOrigin(of: caster) else { return nil }
        return ProjectileShooter(
            key: caster,
            origin: origin,
            aim: ProjectileFlight.normalized(playerCastTarget() - origin),
            isFirstPerson: false,
            location: streamer?.cellLocation(of: caster)
        )
    }

    /// The muzzle an NPC casts from: its own eye, scaled with the actor.
    func actorCastOrigin(of key: ReferenceKey) -> SIMD3<Float>? {
        guard
            let streamer,
            let entry = streamer.referenceEntry(key: key),
            let actor = entry.placedActor
        else { return nil }
        let moved = streamer.npcTransform(for: key)
            ?? worldState.component(ReferenceTransformOverride.self, for: key)
        let feet = moved?.position ?? actor.placement.position
        return feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight * actor.scale)
    }

    /// What an NPC caster aims at: the middle of the player's capsule rather
    /// than the eye or the feet, so a spell that misses does so because the
    /// caster was aiming at a target that moved and not because it was aiming
    /// at the floor.
    func playerCastTarget() -> SIMD3<Float> {
        let player = combat.meleeAttacker
        return player.feet + SIMD3(0, 0, player.capsule.height / 2)
    }

    /// What `caster`'s aim ray reaches, out to `range`.
    ///
    /// Range zero means the record bounds nothing, and then the same
    /// `fVisibleNavmeshMoveDist` ceiling a projectile flies under applies —
    /// past it UESP states a shot "will phase through targets without doing any
    /// damage", so there is nothing further out to hit.
    func aimedTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        guard caster == .player else { return actorAimedTarget(within: range, for: caster) }
        guard let renderer else { return .none }
        let origin = renderer.freeFlyCamera.position
        let direction = ProjectileFlight.normalized(renderer.freeFlyCamera.forward)
        let reach = castReach(within: range)
        let candidates = combat.projectileTargets()
        let impact = ProjectileImpactQuery.first(
            step: ProjectileStep(from: origin, to: origin + direction * reach, radius: 0),
            targets: candidates,
            shooter: .player,
            sweep: { combat.sweepProjectile($0) }
        )
        return SpellAim(
            target: impact?.target,
            position: impact?.position ?? origin + direction * reach,
            candidates: candidates
        )
    }

    /// The same query for an NPC caster, from its eye toward the player.
    private func actorAimedTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        guard let origin = actorCastOrigin(of: caster) else { return .none }
        let direction = ProjectileFlight.normalized(playerCastTarget() - origin)
        let reach = castReach(within: range)
        let candidates = combat.projectileTargets()
        let impact = ProjectileImpactQuery.first(
            step: ProjectileStep(from: origin, to: origin + direction * reach, radius: 0),
            targets: candidates,
            shooter: caster,
            sweep: { combat.sweepProjectile($0) }
        )
        return SpellAim(
            target: impact?.target,
            position: impact?.position ?? origin + direction * reach,
            candidates: candidates
        )
    }

    /// How far a cast of SPIT range `range` actually reaches in this session.
    func castReach(within range: Float) -> Float {
        let ceiling = combat.archery?.settings.visibleMoveDistance.value ?? 0
        return [range, ceiling].filter { $0 > 0 }.min() ?? Self.spellAimFallbackReach
    }

    /// How far an aimed cast reaches when neither the record nor the settings
    /// bound it. The archery ceiling in the vanilla table, so a session with no
    /// GMSTs behaves like one that has them rather than aiming at infinity.
    static let spellAimFallbackReach: Float = 12288
}
