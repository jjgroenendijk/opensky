public import OpenSkyPhysics

/// What the world adapters use of `WalkController`.
public protocol WalkPort {
    var capsule: PlayerCapsule { get }
    var feetPosition: SIMD3<Float> { get }
    var isGrounded: Bool { get }
}
