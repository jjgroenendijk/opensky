// The values the capsule narrowphase reports: one contact, one move result, and
// the world-space triangle both capsule and dynamic-body queries test against.

import OpenSkyFormatsESM
import simd

nonisolated public struct CapsuleCollisionContact: Sendable {
    public let normal: SIMD3<Float>
    public let depth: Float
    /// The MATT material of the shape that produced this contact, so the surface
    /// underfoot can be named. Nil where the shape carries none.
    public let material: FormID?

    public init(normal: SIMD3<Float>, depth: Float, material: FormID? = nil) {
        self.normal = normal
        self.depth = depth
        self.material = material
    }

    /// The same contact attributed to a shape's material. Narrowphase works in
    /// geometry and has no shape to ask, so the material is attached once,
    /// where the shape is still in hand.
    public func naming(_ material: FormID?) -> CapsuleCollisionContact {
        CapsuleCollisionContact(normal: normal, depth: depth, material: material)
    }
}

nonisolated public struct CapsuleMoveResult: Sendable {
    public let position: SIMD3<Float>
    public let contacts: [CapsuleCollisionContact]
    public let hasUnresolvedPenetration: Bool

    public init(
        position: SIMD3<Float>,
        contacts: [CapsuleCollisionContact],
        hasUnresolvedPenetration: Bool
    ) {
        self.position = position
        self.contacts = contacts
        self.hasUnresolvedPenetration = hasUnresolvedPenetration
    }
}

/// Three world-space points. The dynamic-body narrowphase runs the same closest-point
/// query against the same static geometry.
nonisolated public struct CollisionTriangle: Sendable {
    public let first: SIMD3<Float>
    public let second: SIMD3<Float>
    public let third: SIMD3<Float>
}
