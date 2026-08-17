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
    @discardableResult
    func launchSpellProjectile(_ payload: SpellPayload) -> Bool {
        guard
            let runtime = archery.runtime,
            let link = payload.projectile,
            let profile = spellProjectileProfile(link)
        else { return false }
        return runtime.projectiles.fire(
            ProjectileShot.spell(profile: profile, payload: payload)
        ) != nil
    }

    /// What the player's aim ray reaches, out to `range`.
    ///
    /// Range zero means the record bounds nothing, and then the same
    /// `fVisibleNavmeshMoveDist` ceiling a projectile flies under applies —
    /// past it UESP states a shot "will phase through targets without doing any
    /// damage", so there is nothing further out to hit.
    func aimedTarget(within range: Float) -> SpellAim {
        guard let renderer else { return .none }
        let origin = renderer.freeFlyCamera.position
        let direction = ProjectileFlight.normalized(renderer.freeFlyCamera.forward)
        let ceiling = archery.runtime?.settings.visibleMoveDistance.value ?? 0
        let reach = [range, ceiling].filter { $0 > 0 }.min() ?? Self.spellAimFallbackReach
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

    /// How far an aimed cast reaches when neither the record nor the settings
    /// bound it. The archery ceiling in the vanilla table, so a session with no
    /// GMSTs behaves like one that has them rather than aiming at infinity.
    static let spellAimFallbackReach: Float = 12288
}
