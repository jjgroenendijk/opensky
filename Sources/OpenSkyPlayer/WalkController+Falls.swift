// Falls: the highest point of a fall, and the drop reported once the feet land.
// See docs/engine/combat.md#fall-damage.

import OpenSkyRendering

nonisolated extension WalkController {
    /// One fixed step that also records the fall it ends.
    mutating func stepTrackingFall(yaw: Float, input: CameraInput, world: StepWorld) {
        let wasGrounded = isGrounded
        let fallSpeed = -verticalVelocity
        step(yaw: yaw, input: input, dt: Self.fixedTimeStep, world: world)
        trackFall(wasGrounded: wasGrounded, speed: fallSpeed)
    }

    /// The fall that ended since the last call, once.
    public mutating func takeLanding() -> WalkLanding? {
        defer { landing = nil }
        return landing
    }

    private mutating func trackFall(wasGrounded: Bool, speed: Float) {
        guard !isSwimming else {
            fallPeakZ = nil
            return
        }
        guard isGrounded else {
            fallPeakZ = max(fallPeakZ ?? feetPosition.z, feetPosition.z)
            return
        }
        if !wasGrounded, let peak = fallPeakZ {
            landing = WalkLanding(height: peak - feetPosition.z, speed: speed)
        }
        fallPeakZ = nil
    }
}

/// A fall that just ended on solid ground, for the fall damage rule.
nonisolated public struct WalkLanding: Equatable, Sendable {
    /// Game units from the highest point of the fall down to the feet.
    public let height: Float
    /// Downward speed at the moment of landing, units per second.
    public let speed: Float

    public init(height: Float, speed: Float) {
        self.height = height
        self.speed = speed
    }
}
