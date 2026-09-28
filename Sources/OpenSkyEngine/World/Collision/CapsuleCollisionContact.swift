// The values the capsule narrowphase reports: one contact, one move result, and
// the world-space triangle both capsule and dynamic-body queries test against.

import OpenSkyFormats
import simd

nonisolated struct CapsuleCollisionContact {
    let normal: SIMD3<Float>
    let depth: Float
    /// The MATT material of the shape that produced this contact (issue #358),
    /// so the surface the player is standing on can be named. Nil where the
    /// shape carries none.
    let material: FormID?

    init(normal: SIMD3<Float>, depth: Float, material: FormID? = nil) {
        self.normal = normal
        self.depth = depth
        self.material = material
    }

    /// The same contact attributed to a shape's material. Narrowphase works in
    /// geometry and has no shape to ask, so the material is attached once,
    /// where the shape is still in hand.
    func naming(_ material: FormID?) -> CapsuleCollisionContact {
        CapsuleCollisionContact(normal: normal, depth: depth, material: material)
    }
}

nonisolated struct CapsuleMoveResult {
    let position: SIMD3<Float>
    let contacts: [CapsuleCollisionContact]
    let hasUnresolvedPenetration: Bool
}

/// Three world-space points. Shared with the dynamic-body narrowphase
/// (issue #193), which runs the same closest-point query against the same
/// placed static geometry.
nonisolated struct CollisionTriangle {
    let first: SIMD3<Float>
    let second: SIMD3<Float>
    let third: SIMD3<Float>
}
