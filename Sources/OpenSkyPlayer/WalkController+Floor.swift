// Placing the capsule on the floor under a camera that a teleport or a mode switch
// left nearer the floor than the eye height.

import OpenSkyPhysics
import simd

nonisolated extension WalkController {
    /// Lifts the feet onto a walkable floor between them and the eye. A reset from a
    /// camera nearer the floor than the eye height would otherwise start under it.
    public mutating func standOnFloorBelowEye(query: CapsuleWorldCollider.CandidateQuery) {
        let support = CapsuleWorldCollider(capsule: capsule).stepSupport(
            at: SIMD2(feetPosition.x, feetPosition.y),
            minimumHeight: feetPosition.z,
            maximumHeight: cameraPosition.z,
            query: query
        )
        guard let support else { return }
        var feet = feetPosition
        feet.z = support.height
        reset(cameraPosition: feet + SIMD3<Float>(0, 0, capsule.eyeHeight))
    }
}
