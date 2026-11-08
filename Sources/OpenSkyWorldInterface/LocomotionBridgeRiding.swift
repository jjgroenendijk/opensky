import OpenSkyBehavior
import OpenSkyPhysics
import simd

/// How the mount under the rider moved in the last step.
nonisolated public struct MountMotion: Equatable, Sendable {
    /// Horizontal speed, world units per second.
    public var speed: Float = 0
    /// Yaw change of the last step, radians, counter-clockwise.
    public var turnDelta: Float = 0
    public var isSprinting = false
    /// A flying mount's climb angle, radians; positive climbs.
    public var pitch: Float = 0

    public static let still = MountMotion()

    public init(
        speed: Float = 0, turnDelta: Float = 0, isSprinting: Bool = false, pitch: Float = 0
    ) {
        self.speed = speed
        self.turnDelta = turnDelta
        self.isSprinting = isSprinting
        self.pitch = pitch
    }

    public var isMoving: Bool {
        speed > 0.5
    }
}
