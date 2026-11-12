// When a projectile's PROJ alternate trigger sets off its explosion in the air: by
// timer or by proximity. A satellite of `ProjectileRuntime`.
// See docs/formats/explosions.md.

import Foundation
import OpenSkyCombatInterface
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
}
