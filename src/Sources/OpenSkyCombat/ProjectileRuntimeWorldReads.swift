// Two world reads a live projectile makes: the impact chain a landed arrow
// plays, and the eviction of stuck arrows whose cell is gone. A satellite of
// `ProjectileRuntime`, which is at its body-length cap.

import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import simd

extension ProjectileRuntime {
    /// The IPCT chain for a hit, played where the world can play it.
    /// Internal rather than private so it can live here while `resolve` in the
    /// main file calls it.
    func playImpact(of impact: ProjectileImpact, payload: ProjectilePayload) {
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

    /// Drops stuck arrows whose cell is no longer resident, so an unloading
    /// cell takes them with it.
    public func evictUnloadedStuckArrows() {
        guard let world, !stuck.isEmpty else { return }
        let resident = world.residentProjectileCells()
        guard !resident.isEmpty else { return }
        removeStuckArrows(
            stuck.indices.filter { !resident.contains(stuck[$0].arrow.location) }
        )
    }
}
