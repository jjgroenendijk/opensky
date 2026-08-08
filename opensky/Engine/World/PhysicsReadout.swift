// Dynamic rigid-body readout lines (issue #193, roadmap item 15.2), written
// for the M15 gate panel (issue #198) and formatted here rather than in the
// panel section for the reason `RagdollReadout` is: a string a milestone gate
// asserts on belongs in the engine target, where a unit test can reach it
// without a window.
//
// Documented in docs/engine/dynamic-bodies.md.

import Foundation

nonisolated enum PhysicsReadout {
    /// How many bodies exist and how many of them the solver is still paying
    /// for. A sleeping body is the resting state, so the line names both rather
    /// than only the total.
    static func bodyText(for snapshot: DynamicBodyStatsSnapshot) -> String {
        guard snapshot.bodyCount > 0 else {
            return "Bodies: none" + (snapshot.isFrozen ? " (frozen)" : "")
        }
        let frozen = snapshot.isFrozen ? ", frozen" : ""
        return "Bodies: \(snapshot.bodyCount)"
            + " (\(snapshot.activeBodyCount) awake,"
            + " \(snapshot.sleepingBodyCount) asleep\(frozen))"
    }

    /// What the last step cost: contacts resolved and substeps run.
    static func stepText(for snapshot: DynamicBodyStatsSnapshot) -> String {
        "Last step: \(snapshot.contactCount) contacts over \(snapshot.substepCount) substeps"
    }

    /// Non-finite recoveries. Always zero on a healthy run, so the line names
    /// the healthy case rather than printing a bare zero.
    static func recoveryText(for snapshot: DynamicBodyStatsSnapshot) -> String {
        snapshot.recoveredBodyCount == 0
            ? "Stability: no pose recovery needed"
            : "Stability: \(snapshot.recoveredBodyCount) bodies recovered — this is a bug"
    }
}
