// Placing the capsule on the ground under a camera that a teleport or a mode switch
// left at any height.

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

    /// How far below the eye a placement looks for ground: deeper than any drop in Skyrim's
    /// exteriors, so a teleport from high above still lands.
    public static let groundSearchDepth: Float = 16384

    /// The ground a placement stands the feet on: the highest walkable surface, terrain or
    /// collision, at or below the eye. Nil when nothing under the spot has loaded.
    public func groundBelowEye(
        sampleGround: GroundSampler,
        query: CapsuleWorldCollider.CandidateQuery
    ) -> Float? {
        let spot = SIMD2(feetPosition.x, feetPosition.y)
        let eye = cameraPosition.z
        let terrain = sampleGround(spot)?.height
        let support = CapsuleWorldCollider(capsule: capsule).stepSupport(
            at: spot,
            minimumHeight: eye - Self.groundSearchDepth,
            maximumHeight: eye,
            query: query
        )?.height
        let belowEye = [terrain, support].compactMap(\.self).filter { $0 <= eye }
        // Terrain above the eye means the spot is under the landscape: stand on top of it.
        return belowEye.max() ?? terrain
    }

    /// Stands the feet on `groundBelowEye`, so a teleport or a mode switch puts them on
    /// the ground instead of dropping them from the placed height.
    @discardableResult
    public mutating func standOnGround(
        sampleGround: GroundSampler,
        query: CapsuleWorldCollider.CandidateQuery
    ) -> Bool {
        guard let ground = groundBelowEye(sampleGround: sampleGround, query: query) else {
            return false
        }
        var feet = feetPosition
        feet.z = ground
        reset(cameraPosition: feet + SIMD3<Float>(0, 0, capsule.eyeHeight))
        return true
    }
}
