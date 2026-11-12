// The eviction of stuck arrows whose cell is gone. A satellite of `ProjectileRuntime`.

import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import simd

extension ProjectileRuntime {
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
