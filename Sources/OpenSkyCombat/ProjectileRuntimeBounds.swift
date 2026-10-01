// Transient caps on projectiles, enforced by the combat loop. `live` and `stuck` are
// append-only, so index 0 is the oldest. Corpses and bodies are capped by their own
// registries (docs/engine/combat.md).

import Foundation

extension ProjectileRuntime {
    /// Cancels the oldest projectiles until at most `limit` fly. Each is traced as
    /// `.cancelled`, so a capped shot stays visible. Returns the count.
    @discardableResult
    public func trimLive(to limit: Int) -> Int {
        let excess = live.count - max(0, limit)
        guard excess > 0 else { return 0 }
        for projectile in live.prefix(excess) {
            record(projectile, outcome: .cancelled, at: projectile.position, impact: nil)
        }
        removeOldestLive(excess)
        return excess
    }

    /// Pulls the oldest stuck arrows out of the world until at most `limit`
    /// remain standing. Oldest first for the same reason and with the same
    /// exactness: `stuck` is append-only.
    ///
    /// - Returns: how many were removed.
    @discardableResult
    public func trimStuck(to limit: Int) -> Int {
        let excess = stuck.count - max(0, limit)
        guard excess > 0 else { return 0 }
        removeStuckArrows(Array(stuck.indices.prefix(excess)))
        return excess
    }
}
