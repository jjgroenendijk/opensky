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
    /// `fMineExteriorRadiusMult`: a mine outdoors reaches this much farther.
    static let exteriorMineReach: Float = 1.6

    /// The contact an alternate trigger makes at the projectile's position, or nil. A
    /// proximity shot starts its fuse when a hostile living actor comes near, and goes
    /// off when the fuse burns out.
    func alternateDetonation(
        of projectile: inout LiveProjectile, dt: Float
    ) -> ProjectileImpact? {
        let profile = projectile.profile
        guard profile.explosion != nil else { return nil }
        let timerFired = profile.explosionTimer > 0 && projectile.state.age >= profile
            .explosionTimer
        let reach = profile.explosionProximity
            * (world?.projectileIsOutdoors == true ? Self.exteriorMineReach : 1)
        if reach > 0, !projectile.fuse.isBurning, let world {
            let near = world.mineTriggers(for: projectile.shooter)
                .filter { $0.key != projectile.shooter }
                .filter { !(projectile.fuse.ignoresPlayer && $0.key == .player) }
                .map { (key: $0.key, distance: simd_distance($0.feet, projectile.position)) }
                .filter { $0.distance <= reach }
                .sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }
            for target in near where !projectile.fuse.isBurning {
                projectile.fuse.notice(target.key, playerRoll: world.playerSetsOffMine)
            }
        }
        let burnedOut = projectile.fuse.burn(dt)
        guard timerFired || burnedOut else { return nil }
        return ProjectileImpact(
            distance: 0, position: projectile.position, target: nil, reference: nil
        )
    }
}
