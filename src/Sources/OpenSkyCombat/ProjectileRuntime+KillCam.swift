// A player's shot that passes the kill cam's release check turns toward its target.
// See docs/engine/kill-cam.md#bow-and-spell-kill-cams-in-the-game.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

extension ProjectileRuntime {
    /// Re-launches `projectile` turned by at most 15 degrees toward the ballistic aim at
    /// the kill cam's target, when the release check passes.
    func turnForKillCam(
        _ projectile: inout LiveProjectile, shot: ProjectileShot, aimTarget: ReferenceKey?
    ) {
        guard let aim = world?.projectileKillCamAim(for: projectile, aimTarget: aimTarget)
        else { return }
        let origin = projectile.launchPosition
        let gravity = ProjectileFlight.worldGravity * shot.flightProfile.gravityFactor
        let ballistic = NPCArcheryAim.ballistic(
            from: origin, to: aim, speed: simd_length(projectile.state.velocity), gravity: gravity
        )
        projectile.state = ProjectileFlight.launch(
            from: origin,
            along: ProjectileAutoAim.turned(
                projectile.launchDirection, toward: ballistic,
                atMost: RangedKillCam.largestTurnDegrees
            ),
            profile: shot.flightProfile,
            speedScale: shot.speedScale
        )
    }
}
