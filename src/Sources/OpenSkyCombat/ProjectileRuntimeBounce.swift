// An arrow that lands on a material that does not hold arrows, or that a shield
// deflects, bounces: it leaves along its flight reflected about the surface, at a
// tenth of the `PROJ` speed, and does not stick. A satellite of `ProjectileRuntime`.
// See docs/engine/projectiles.md#pick-up-bounce-and-stick-in-the-game.

import Foundation
import OpenSkyCombatInterface
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

extension ProjectileRuntime {
    /// Whether a landed arrow bounces instead of sticking. A hit on an actor that took
    /// no damage was deflected by a shield.
    func bounces(
        _ projectile: LiveProjectile, at impact: ProjectileImpact,
        landing: ProjectilePayloadLanding.Report
    ) -> Bool {
        guard projectile.payload.arrow != nil else { return false }
        guard impact.isActor else { return !arrows.holds(material: impact.material) }
        return landing.keptArrow == nil
    }

    /// Sends the arrow on along its reflected flight. It lands again later, harmless.
    func bounce(_ projectile: LiveProjectile, off impact: ProjectileImpact) {
        let direction = Self.reflected(projectile.state.velocity, about: impact.normal)
        var bounced = projectile
        bounced.hasBounced = true
        bounced.bouncedOff = impact.target
        let share = arrows.bounceSpeedShare.isFinite ? max(0, arrows.bounceSpeedShare) : 0
        let speed = simd_length(projectile.state.velocity) > 0 ? share : 0
        var state = ProjectileFlight.launch(
            from: impact.position + direction * Self.bounceClearance,
            along: direction, profile: projectile.profile, speedScale: speed
        )
        state.travelled = projectile.state.travelled
        state.age = projectile.state.age
        bounced.state = state
        pendingBounces.append(bounced)
    }

    /// A bounced arrow's next landing: it lies where it came down, and an actor it
    /// falls on keeps nothing.
    func settle(_ projectile: LiveProjectile, at impact: ProjectileImpact) -> ProjectileTrace {
        let lies = !impact.isActor && stick(projectile, at: impact, lying: true)
        return record(
            projectile, outcome: impact.isActor ? .hitActor : .hitStatic,
            at: impact.position, impact: impact, stuck: lies
        )
    }

    /// How far off the surface a bounce starts, so its first step does not touch it again.
    static let bounceClearance: Float = 1

    /// `velocity`'s direction mirrored about `normal`; straight back without one.
    static func reflected(_ velocity: SIMD3<Float>, about normal: SIMD3<Float>?) -> SIMD3<Float> {
        let length = simd_length(velocity)
        guard length > 0, length.isFinite else { return SIMD3(0, 0, 1) }
        let direction = velocity / length
        guard let normal, simd_length(normal) > 0 else { return -direction }
        let unit = simd_normalize(normal)
        return direction - 2 * simd_dot(direction, unit) * unit
    }
}

extension ProjectileRuntime {
    /// Where an NPC aims a spell at `point`: the tracker noise of
    /// `NPCArcheryAim.spellAimVariance`. See docs/engine/archery.md#npc-archers.
    public func npcSpellAim(at point: SIMD3<Float>, concentration: Bool) -> SIMD3<Float> {
        NPCArcheryAim.noisy(
            point, random: &spellAimRandom,
            variance: NPCArcheryAim.spellAimVariance(concentration: concentration)
        )
    }
}

extension ProjectileRuntime {
    /// The shots in the air, the arrows standing, and the newest landings.
    var readout: ProjectileReadout {
        var readout = ProjectileReadout()
        readout.inFlight = live.count
        readout.bouncing = live.count(where: \.hasBounced)
        readout.stuck = stuck.compactMap(\.key)
        readout.landings = trace.map { entry in
            var landing = ProjectileReadout.Landing(
                outcome: entry.outcome.rawValue, position: entry.endPosition
            )
            landing.target = entry.target
            landing.material = entry.material
            landing.stuck = entry.stuck
            landing.bounced = entry.bounced
            landing.damage = entry.appliedDamage
            landing.spellTargets = entry.spellHit?.targetCount
            landing.spellEntries = entry.spellHit?.entryCount
            landing.spellRefusals = entry.spellHit?.refusals.count
            landing.spellMagnitudes = entry.spellHit?.adjustments
                .map { $0.baseMagnitude * $0.multiplier } ?? []
            landing.spellLanded = entry.spellHit?.landedCount
            landing.spellSkipped = entry.spellHit?.skippedCount
            landing.spellHealthTaken = entry.spellHit?.healthTaken
            landing.spellOutcomes = entry.spellHit?.entryOutcomes ?? []
            return landing
        }
        return readout
    }
}
