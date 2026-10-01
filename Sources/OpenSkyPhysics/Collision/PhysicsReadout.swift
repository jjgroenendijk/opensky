// Dynamic rigid-body readout lines, formatted in the engine target so a unit test can
// check them without a window. See docs/engine/dynamic-bodies.md.

import Foundation

nonisolated public enum PhysicsReadout: Sendable {
    /// How many bodies exist and how many of them the solver is still paying
    /// for. A sleeping body is the resting state, so the line names both rather
    /// than only the total.
    public static func bodyText(for snapshot: DynamicBodyStatsSnapshot) -> String {
        guard snapshot.bodyCount > 0 else {
            return "Bodies: none" + (snapshot.isFrozen ? " (frozen)" : "")
        }
        let frozen = snapshot.isFrozen ? ", frozen" : ""
        return "Bodies: \(snapshot.bodyCount)"
            + " (\(snapshot.activeBodyCount) awake,"
            + " \(snapshot.sleepingBodyCount) asleep\(frozen))"
    }

    /// What the last step cost: contacts resolved and substeps run.
    public static func stepText(for snapshot: DynamicBodyStatsSnapshot) -> String {
        "Last step: \(snapshot.contactCount) contacts over \(snapshot.substepCount) substeps"
    }

    /// Non-finite recoveries. Always zero on a healthy run, so the line names
    /// the healthy case rather than printing a bare zero.
    public static func recoveryText(for snapshot: DynamicBodyStatsSnapshot) -> String {
        snapshot.recoveredBodyCount == 0
            ? "Stability: no pose recovery needed"
            : "Stability: \(snapshot.recoveredBodyCount) bodies recovered — this is a bug"
    }
}
