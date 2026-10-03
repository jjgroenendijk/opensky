// A projectile's explosion: on impact, or in the air when the PROJ alternate
// trigger's timer or proximity fires. A satellite of `ProjectileRuntime`.
// See docs/formats/explosions.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

extension ProjectileRuntime {
    /// The contact an alternate trigger makes at the projectile's position, or nil.
    func alternateDetonation(of projectile: LiveProjectile) -> ProjectileImpact? {
        let profile = projectile.profile
        guard profile.explosion != nil else { return nil }
        let timerFired = profile.explosionTimer > 0 && projectile.state.age >= profile
            .explosionTimer
        let proximity = profile.explosionProximity
        let nearby = proximity > 0 && (world?.projectileTargets().contains { target in
            target.key != projectile.shooter
                && simd_distance(target.feet, projectile.position) <= proximity
        } ?? false)
        guard timerFired || nearby else { return nil }
        return ProjectileImpact(
            distance: 0, position: projectile.position, target: nil, reference: nil
        )
    }

    /// Sets off the projectile's explosion at `position`. A spell's projectile is a spell
    /// cause; anything else is a projectile cause.
    @discardableResult
    func detonateExplosion(
        of projectile: LiveProjectile,
        at position: SIMD3<Float>
    ) -> ExplosionReport? {
        guard
            let explosions,
            let spec = explosions.spec(itemLink: projectile.profile.explosion)
        else { return nil }
        return explosions.detonate(
            spec, at: position, cause: projectile.payload.spell == nil ? .projectile : .spell
        )
    }
}
