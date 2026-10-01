// Ragdoll readout lines, formatted in the engine target so a unit test can check them
// without a window. See docs/engine/ragdoll.md.

import Foundation
import OpenSkyPhysics

nonisolated public enum RagdollReadout: Sendable {
    /// How many corpses are simulating, and how many have stopped.
    public static func ragdollText(for snapshot: RagdollStatsSnapshot) -> String {
        guard snapshot.ragdollCount > 0 else {
            return "Ragdolls: none" + (snapshot.isFrozen ? " (frozen)" : "")
        }
        let frozen = snapshot.isFrozen ? ", frozen" : ""
        return "Ragdolls: \(snapshot.ragdollCount)"
            + " (\(snapshot.activeRagdollCount) active,"
            + " \(snapshot.settledRagdollCount) settled\(frozen))"
    }

    /// The bone-body readout.
    public static func boneBodyText(for snapshot: RagdollStatsSnapshot) -> String {
        "Bone bodies: \(snapshot.boneBodyCount) over \(snapshot.jointCount) joints"
    }

    /// The constraint-iteration readout, with the violation count beside it so
    /// the two read together: iterations are what the solver spends, violations
    /// are what it had left when it stopped spending.
    public static func solverText(for snapshot: RagdollStatsSnapshot) -> String {
        let violations = snapshot.jointViolationCount
        let converged = violations == 0 ? "converged" : "\(violations) limits still violated"
        return "Solver: \(snapshot.solverIterationCount) iterations/substep, \(converged)"
    }

    /// What the biped filter admitted and what touches now, so "nothing touching" differs
    /// from "nothing allowed".
    public static func selfCollisionText(for snapshot: RagdollStatsSnapshot) -> String {
        guard snapshot.isSelfCollisionEnabled else {
            return "Self-collision: off"
        }
        return "Self-collision: \(snapshot.selfCollisionPairCount) bone pairs admitted, "
            + "\(snapshot.selfContactCount) touching"
    }

    /// Non-finite recoveries. Always zero on a healthy run, so the line names
    /// the healthy case rather than printing a bare zero.
    public static func recoveryText(for snapshot: RagdollStatsSnapshot) -> String {
        snapshot.recoveredBodyCount == 0
            ? "Stability: no pose recovery needed"
            : "Stability: \(snapshot.recoveredBodyCount) bodies recovered — this is a bug"
    }
}
