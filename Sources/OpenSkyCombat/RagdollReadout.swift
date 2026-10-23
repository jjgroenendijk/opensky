// Ragdoll readout lines, formatted in the engine target so a unit test can check them
// without a window. See docs/engine/ragdoll.md.

import Foundation
import OpenSkyPhysics

nonisolated public enum RagdollReadout: Sendable {
    /// What the biped filter admitted and what touches now, so "nothing touching" differs
    /// from "nothing allowed".
    public static func selfCollisionText(for snapshot: RagdollStatsSnapshot) -> String {
        guard snapshot.isSelfCollisionEnabled else {
            return "Bone collision: off"
        }
        return "Bone collision: \(snapshot.selfCollisionPairCount) pairs allowed, "
            + "\(snapshot.selfContactCount) touching"
    }
}
