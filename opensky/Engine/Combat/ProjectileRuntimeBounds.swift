// Transient caps on projectiles (issue #374, roadmap item 15.7, scope point 5).
//
// A satellite of `ProjectileRuntime` because that type is at its body-length
// limit, and because these two are the only members it has that exist for
// something other than archery: the combat loop enforces them, archery itself
// never asks. `record(_:outcome:at:impact:)` and `removeStuckArrows(_:)` are
// internal on the parent for exactly this reason.
//
// Oldest first is exact rather than approximate for both populations: `live` and
// `stuck` are appended to and never reordered, so index 0 is the one that has
// been around longest. The other two populations the loop caps — corpses and
// awake bodies — are trimmed by their own registries; see
// docs/engine/combat.md for the whole table and why the orders differ.

import Foundation

extension ProjectileRuntime {
    /// Cancels the oldest projectiles until at most `limit` are in the air.
    ///
    /// Oldest first is exact here rather than approximate: `live` is appended
    /// to on every shot and never reordered, so index 0 is the arrow that has
    /// been flying longest. A cancelled projectile is recorded in the trace as
    /// `.cancelled`, the same outcome a save gives one, so a capped shot is
    /// visible rather than silently absent.
    ///
    /// - Returns: how many were cancelled.
    @discardableResult
    func trimLive(to limit: Int) -> Int {
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
    func trimStuck(to limit: Int) -> Int {
        let excess = stuck.count - max(0, limit)
        guard excess > 0 else { return 0 }
        removeStuckArrows(Array(stuck.indices.prefix(excess)))
        return excess
    }
}
