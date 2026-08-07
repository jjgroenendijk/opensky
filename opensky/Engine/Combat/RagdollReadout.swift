// Ragdoll readout lines (issue #197, roadmap item 15.6), formatted here rather
// than in the panel section for the reason `ArcheryReadout` and
// `MeleeCombatReadout` are: a string a milestone gate asserts on belongs in the
// engine target, where a unit test can reach it without a window.
//
// Documented in docs/engine/ragdoll.md.

import Foundation

nonisolated enum RagdollReadout {
    /// How many corpses are simulating, and how many have stopped.
    static func ragdollText(for snapshot: RagdollStatsSnapshot) -> String {
        guard snapshot.ragdollCount > 0 else {
            return "Ragdolls: none" + (snapshot.isFrozen ? " (frozen)" : "")
        }
        let frozen = snapshot.isFrozen ? ", frozen" : ""
        return "Ragdolls: \(snapshot.ragdollCount)"
            + " (\(snapshot.activeRagdollCount) active,"
            + " \(snapshot.settledRagdollCount) settled\(frozen))"
    }

    /// The bone-body readout item 15.6 scope point 7 asks for.
    static func boneBodyText(for snapshot: RagdollStatsSnapshot) -> String {
        "Bone bodies: \(snapshot.boneBodyCount) over \(snapshot.jointCount) joints"
    }

    /// The constraint-iteration readout, with the violation count beside it so
    /// the two read together: iterations are what the solver spends, violations
    /// are what it had left when it stopped spending.
    static func solverText(for snapshot: RagdollStatsSnapshot) -> String {
        let violations = snapshot.jointViolationCount
        let converged = violations == 0 ? "converged" : "\(violations) limits still violated"
        return "Solver: \(snapshot.solverIterationCount) iterations/substep, \(converged)"
    }

    /// Non-finite recoveries. Always zero on a healthy run, so the line names
    /// the healthy case rather than printing a bare zero.
    static func recoveryText(for snapshot: RagdollStatsSnapshot) -> String {
        snapshot.recoveredBodyCount == 0
            ? "Stability: no pose recovery needed"
            : "Stability: \(snapshot.recoveredBodyCount) bodies recovered — this is a bug"
    }
}
