// Placing the capsule on the floor under a camera that a teleport or a mode switch
// left nearer the floor than the eye height.

import OpenSkyPhysics
import OpenSkyRenderCore
import simd

nonisolated extension WalkController {
    /// `sampleGround` answering a repeat of its last position from memory. A step samples
    /// where it aims and where it lands, which is the same place unless something blocked it.
    static func remembering(_ sampleGround: @escaping GroundSampler) -> GroundSampler {
        var last: (position: SIMD2<Float>, sample: TerrainGroundSample?)?
        return { position in
            if let last, last.position == position {
                return last.sample
            }
            let sample = sampleGround(position)
            last = (position, sample)
            return sample
        }
    }

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
