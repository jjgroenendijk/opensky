// Two world reads a live projectile makes: the impact chain a landed arrow
// plays, and the eviction of stuck arrows whose cell is gone. A satellite of
// `ProjectileRuntime`, which is at its body-length cap.

import OpenSkyFormatsESM
import simd

extension ProjectileRuntime {
    /// The IPCT chain for a hit, played where the world can play it.
    /// Internal rather than private so it can live here while `resolve` in the
    /// main file calls it.
    public func playImpact(at position: SIMD3<Float>) -> FormID? {
        guard let world, let impacts else { return nil }
        // An arrow resolves impact through the ammunition's chain. AMMO has no INAM, so
        // the unarmed profile's nil data set is what an arrow carries. The lookup stays,
        // so an AMMO impact link is a one-line change.
        guard
            let resolved = impacts.resolve(
                weapon: .unarmed, material: world.projectileMaterial()
            )
        else { return nil }
        world.playProjectileImpact(resolved, at: position)
        return resolved.sound
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
