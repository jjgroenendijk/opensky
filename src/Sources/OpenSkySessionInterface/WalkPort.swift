public import OpenSkyPhysics

/// What the world adapters use of `WalkController`.
public protocol WalkPort {
    var capsule: PlayerCapsule { get }
    var feetPosition: SIMD3<Float> { get }
    var isGrounded: Bool { get }
    var isSwimming: Bool { get }
    var verticalVelocity: Float { get }
    var groundNormal: SIMD3<Float>? { get }
    var activeStepSupport: CapsuleStepSupport? { get }
    var isHeldAtEdge: Bool { get }
    var hasUnresolvedPenetration: Bool { get }
}
