// The powered-ragdoll motor: during the hand-off blend it pulls each bone body
// back towards the pose the animation held. It acts on velocity, not with a
// Havok constraint motor, so it is an approximation. See docs/engine/ragdoll.md.

import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import simd

/// The motor settings of one `hkbPoweredRagdollControlsModifier`, in engine units.
nonisolated public struct RagdollMotor: Equatable, Sendable {
    /// How much of the gap to the target velocity one step closes, `0 ... 1`.
    public var tau: Float
    /// How much of the body's own velocity one second removes.
    public var damping: Float
    /// The largest force the motor applies to one body. Zero means no limit.
    public var maxForce: Float
    /// Target speed per unit of distance from the target pose, per second.
    public var proportionalRecoveryVelocity: Float
    /// Target speed added to the proportional part, in engine units per second.
    public var constantRecoveryVelocity: Float

    public init(
        tau: Float,
        damping: Float,
        maxForce: Float,
        proportionalRecoveryVelocity: Float,
        constantRecoveryVelocity: Float
    ) {
        self.tau = Self.finite(tau)
        self.damping = Self.finite(damping)
        self.maxForce = Self.finite(maxForce)
        self.proportionalRecoveryVelocity = Self.finite(proportionalRecoveryVelocity)
        self.constantRecoveryVelocity = Self.finite(constantRecoveryVelocity)
    }

    /// Havok stores the force and the constant speed in metres; the engine uses
    /// game units, so both are scaled by `havokToEngineScale`.
    public init(_ controls: HKBPoweredRagdollControlsModifier) {
        let scale = NIFCollisionModel.havokToEngineScale
        self.init(
            tau: controls.tau,
            damping: controls.damping,
            maxForce: controls.maxForce * scale,
            proportionalRecoveryVelocity: controls.proportionalRecoveryVelocity,
            constantRecoveryVelocity: controls.constantRecoveryVelocity * scale
        )
    }

    /// The velocity after one step of pulling towards a target `error` away.
    /// `weight` is how much the motor still drives, `0 ... 1`.
    public func driven(
        _ velocity: SIMD3<Float>,
        error: SIMD3<Float>,
        mass: Float,
        dt: Float,
        weight: Float
    ) -> SIMD3<Float> {
        let amount = min(max(weight, 0), 1)
        guard dt > 0, dt.isFinite, amount > 0 else { return velocity }
        let distance = simd_length(error)
        var target = SIMD3<Float>.zero
        if distance > .ulpOfOne {
            let speed = distance * proportionalRecoveryVelocity + constantRecoveryVelocity
            target = error / distance * min(speed, distance / dt)
        }
        let gain = min(max(tau, 0), 1) * amount
        let braking = min(max(damping, 0) * dt, 1) * amount
        var change = (target - velocity) * gain - velocity * braking
        if maxForce > 0, mass > 0 {
            let limit = maxForce * dt / mass
            let size = simd_length(change)
            if size > limit {
                change *= limit / size
            }
        }
        return velocity + change
    }

    /// The rotation that turns `current` into `target`, as axis times angle, along
    /// the shorter way round.
    public static func angularError(
        from current: simd_quatf,
        to target: simd_quatf
    ) -> SIMD3<Float> {
        var delta = target * current.inverse
        if delta.real < 0 {
            delta = simd_quatf(vector: -delta.vector)
        }
        let angle = delta.angle
        guard angle.isFinite, angle > .ulpOfOne else { return .zero }
        return delta.axis * angle
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}
