public import OpenSkyPhysics
public import OpenSkyWorldInterface

/// What the world adapters use of `LocomotionStatus`.
public protocol LocomotionStatusPort {
    var feetPosition: SIMD3<Float> { get set }
    var gait: LocomotionGait { get }
    var graphAvailable: Bool { get set }
    var horizontalVelocity: SIMD2<Float> { get set }
    var isGrounded: Bool { get set }
    var lastPlan: LocomotionStepPlan { get }
    var missingEvents: [String] { get }
    var raisedEvents: [String] { get }
    var recentGraphEvents: [String] { get }
    var verticalVelocity: Float { get }
    var yaw: Float { get }
}
