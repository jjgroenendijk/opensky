// `SpellHitApplying` and the two aimed-delivery answers (issue #471, roadmap
// item 19.8): where a cast spell's projectile comes from, what the caster's aim
// ray reaches, and how a landed spell becomes applied effects.
//
// One conformance for both seams. `ProjectileWorld` and `CasterWorld` each
// refine `SpellHitApplying`, and this controller is both, so a spell that
// arrived as a projectile and one that was cast straight at an actor take the
// same path into `ActiveEffectRuntime` — exactly the reason `reportScriptHit`
// is implemented once for melee, archery and the combat loop.
//
// Two answers are honest partial ones and are worth stating rather than
// papering over:
//
// * `aimedSpellTarget(within:)` finds actors and static geometry along the
//   camera ray with the same queries a projectile's step uses, so a target
//   behind a wall is not reachable. It does *not* model the aim assist vanilla
//   applies to a cast, because nothing in this engine models it for an arrow
//   either.
// * The PROJ lookup goes through the archery item index, which is the one PROJ
//   index this session builds. A session with no item index — every synthetic
//   scene — fires no spell projectile and the caster tally counts the refusal.

import AppKit
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
        archery.items?.projectileProfile(id)
    }

    /// Launches a cast spell's projectile through the archery pipeline.
    ///
    /// The same `ProjectileRuntime` an arrow flies through, so a spell
    /// projectile obeys the same fixed step, the same range and lifetime bounds
    /// and the same impact query — which is the whole point of generalizing the
    /// shot model rather than writing a second one.
    ///
    /// The caster is the payload's own, so an NPC's spell leaves the NPC
    /// (issue #473) rather than the camera: a fireball that spawned at the
    /// player's eye and flew at the player would be a shot nobody could read.
    @discardableResult
    func launchSpellProjectile(_ payload: SpellPayload) -> Bool {
        guard
            let runtime = archery.runtime,
            let link = payload.projectile,
            let profile = spellProjectileProfile(link),
            let shooter = spellShooter(for: payload.caster)
        else { return false }
        return runtime.projectiles.fire(
            ProjectileShot.spell(profile: profile, payload: payload),
            from: shooter
        ) != nil
    }

    /// Where `caster` casts from and which way, or nil when this session
    /// cannot place it.
    ///
    /// The player casts down the camera ray, which is what the reticle
    /// promises. Every other actor casts from its own eye at the actor it is
    /// fighting, which in this build is always the player — `StartCombat`
    /// refuses any other target and item 16.7 says so rather than
    /// half-simulating a fight between two NPCs.
    func spellShooter(for caster: ReferenceKey) -> ProjectileShooter? {
        guard caster != .player else { return projectileShooter }
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
        let player = meleeAttacker
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
        let candidates = projectileTargets()
        let impact = ProjectileImpactQuery.first(
            step: ProjectileStep(from: origin, to: origin + direction * reach, radius: 0),
            targets: candidates,
            shooter: .player,
            sweep: { sweepProjectile($0) }
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
        let candidates = projectileTargets()
        let impact = ProjectileImpactQuery.first(
            step: ProjectileStep(from: origin, to: origin + direction * reach, radius: 0),
            targets: candidates,
            shooter: caster,
            sweep: { sweepProjectile($0) }
        )
        return SpellAim(
            target: impact?.target,
            position: impact?.position ?? origin + direction * reach,
            candidates: candidates
        )
    }

    /// How far a cast of SPIT range `range` actually reaches in this session.
    func castReach(within range: Float) -> Float {
        let ceiling = archery.runtime?.settings.visibleMoveDistance.value ?? 0
        return [range, ceiling].filter { $0 > 0 }.min() ?? Self.spellAimFallbackReach
    }

    /// How far an aimed cast reaches when neither the record nor the settings
    /// bound it. The archery ceiling in the vanilla table, so a session with no
    /// GMSTs behaves like one that has them rather than aiming at infinity.
    static let spellAimFallbackReach: Float = 12288
}
