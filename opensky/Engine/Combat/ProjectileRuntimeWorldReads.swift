// Two reads a live projectile makes of the world around it: the impact chain a
// landed arrow plays, and the eviction of stuck arrows whose cell has gone.
//
// A satellite of `ProjectileRuntime` for the reason `ProjectileRuntimeBounds`
// is one: that type sits at its body-length limit (issue #374), so a function
// added to it has to displace one. These two were chosen because neither
// writes a `private(set)` member of the main type — `playImpact` only reads,
// and the eviction goes through the already-internal
// `removeStuckArrows(_:)` — so moving them needed no access loosened.

import simd

extension ProjectileRuntime {
    /// The IPCT chain for a hit, played where the world can play it.
    /// Internal rather than private so it can live here while `resolve` in the
    /// main file calls it.
    func playImpact(at position: SIMD3<Float>) -> FormID? {
        guard let world, let impacts else { return nil }
        // An arrow resolves its impact through the *ammunition's* chain rather
        // than a bow's: item 15.4 built the resolver around a
        // `MeleeWeaponProfile`, and an arrow has no INAM of its own, so the
        // unarmed profile's nil data set is what an arrow honestly carries
        // until AMMO grows an impact link. The lookup is left in place so that
        // adding one is a one-line change rather than a new chain.
        guard
            let resolved = impacts.resolve(
                weapon: .unarmed, material: world.projectileMaterial(at: position)
            )
        else { return nil }
        world.playProjectileImpact(resolved, at: position)
        return resolved.sound
    }

    /// Drops stuck arrows whose cell is no longer resident, so an unloading
    /// cell takes them with it.
    func evictUnloadedStuckArrows() {
        guard let world, !stuck.isEmpty else { return }
        let resident = world.residentProjectileCells()
        guard !resident.isEmpty else { return }
        removeStuckArrows(
            stuck.indices.filter { !resident.contains(stuck[$0].arrow.location) }
        )
    }
}
