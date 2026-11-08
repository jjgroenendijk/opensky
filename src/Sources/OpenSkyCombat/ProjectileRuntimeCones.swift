// A cone or flame projectile, such as Flames or Unrelenting Force: it hits actors on
// every step, but meets the world only through a look ahead of
// `fConeProjectileEnvironmentDistance` every `fConeProjectileEnvironmentTimer` seconds.
// See docs/engine/spell-delivery.md.

import Foundation
import OpenSkyCombatInterface
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

extension ProjectileRuntime {
    /// Looks ahead along the flight when the timer is due, and notes where the world is.
    func lookAhead(_ projectile: inout LiveProjectile) {
        guard projectile.state.age >= projectile.nextConeLook, let world else { return }
        projectile.nextConeLook = projectile.state.age + max(magicWorld.coneEnvironmentTimer, 0)
        let direction = ProjectileFlight.normalized(projectile.state.velocity)
        let distance = max(magicWorld.coneEnvironmentDistance, 0)
        guard distance > 0, simd_length_squared(direction) > 0 else { return }
        let hit = world.sweepProjectile(
            ShapeSweepQuery.sphere(
                center: projectile.position, radius: 0, direction: direction,
                maximumDistance: distance
            )
        )
        projectile.coneStop = hit.map { projectile.state.travelled + $0.distance }
        projectile.coneWall = hit?.reference
        projectile.coneWallMaterial = hit?.material
    }

    /// The first actor this step touches, else the wall the look ahead found once the
    /// cone reaches it.
    func coneImpact(
        of projectile: LiveProjectile, from previous: SIMD3<Float>, targets: [MeleeTarget]
    ) -> ProjectileImpact? {
        let actor = ProjectileImpactQuery.firstActor(
            from: previous, to: projectile.position,
            radius: projectile.profile.collisionRadius, targets: targets,
            shooter: projectile.shooter
        )
        if let actor {
            return actor
        }
        guard let stop = projectile.coneStop, projectile.state.travelled >= stop else {
            return nil
        }
        let overshoot = projectile.state.travelled - stop
        let back = ProjectileFlight.normalized(projectile.state.velocity) * overshoot
        return ProjectileImpact(
            distance: simd_distance(previous, projectile.position) - overshoot,
            position: projectile.position - back, target: nil,
            reference: projectile.coneWall, material: projectile.coneWallMaterial,
            normal: -ProjectileFlight.normalized(projectile.state.velocity)
        )
    }
}
