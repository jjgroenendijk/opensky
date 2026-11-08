// The powered-ragdoll motor: it pulls towards the target, fades with the blend,
// respects its force limit, and measures rotation the short way round.

@testable import OpenSkyPhysics
import simd
import Testing

struct RagdollMotorTests {
    private static let motor = RagdollMotor(
        tau: 0.5,
        damping: 0,
        maxForce: 0,
        proportionalRecoveryVelocity: 2,
        constantRecoveryVelocity: 1
    )

    @Test
    func pullsTowardsTheTarget() {
        let velocity = Self.motor.driven(
            .zero, error: SIMD3(10, 0, 0), mass: 1, dt: 1 / 60, weight: 1
        )
        #expect(velocity.x > 0)
        #expect(velocity.y == 0)
        #expect(velocity.x <= 10 * 60)
    }

    @Test
    func doesNothingOnceTheSimulationOwnsThePose() {
        let start = SIMD3<Float>(3, -2, 1)
        let velocity = Self.motor.driven(
            start, error: SIMD3(10, 0, 0), mass: 1, dt: 1 / 60, weight: 0
        )
        #expect(velocity == start)
    }

    @Test
    func keepsTheChangeInsideTheForceLimit() {
        var motor = Self.motor
        motor.tau = 1
        motor.maxForce = 2
        let velocity = motor.driven(.zero, error: SIMD3(100, 0, 0), mass: 4, dt: 1, weight: 1)
        #expect(simd_length(velocity) <= 0.5 + 1e-5)
    }

    @Test
    func measuresRotationTheShortWayRound() {
        let quarterTurn = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        let error = RagdollMotor.angularError(
            from: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), to: quarterTurn
        )
        #expect(abs(error.z - .pi / 2) < 1e-4)
        let flipped = simd_quatf(vector: -quarterTurn.vector)
        let same = RagdollMotor.angularError(
            from: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), to: flipped
        )
        #expect(simd_distance(error, same) < 1e-4)
    }

    @Test
    func replacesNonFiniteSettingsWithZero() {
        let motor = RagdollMotor(
            tau: .nan, damping: .infinity, maxForce: 1,
            proportionalRecoveryVelocity: 1, constantRecoveryVelocity: 1
        )
        #expect(motor.tau == 0)
        #expect(motor.damping == 0)
    }
}
