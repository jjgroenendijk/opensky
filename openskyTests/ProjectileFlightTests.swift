// The flight model (issue #196, roadmap item 15.5, scope point 3).
//
// The issue's acceptance asks for "deterministic tests [that] pin a full
// trajectory (spawn, apex, impact point) for synthetic PROJ values", so the
// expectations here are written out longhand from the closed form rather than
// recomputed from the helper under test:
//
//     p(t) = p0 + v0 t + 1/2 a t^2      a = -worldGravity * gravityFactor
//
// Synthetic numbers throughout, chosen so the arithmetic is exact in binary:
// speed 1000 units/s and a gravity factor that makes the acceleration 1400
// units/s^2 — `WalkController.gravity` itself.

@testable import opensky
import simd
import Testing

struct ProjectileFlightTests {
    /// Acceleration exactly `WalkController.gravity`, so every figure below is
    /// a round number.
    private let profile = ProjectileProfile(speed: 1000, gravityFactor: 1, range: 5000)

    @Test func launchPointsTheVelocityAlongTheAimRayAtTheRecordsSpeed() {
        let state = ProjectileFlight.launch(
            from: SIMD3(10, 20, 30), along: SIMD3(2, 0, 0), profile: profile
        )

        #expect(state.position == SIMD3(10, 20, 30))
        // The direction is normalized, so a length-2 vector still launches at
        // the record's own speed.
        #expect(state.velocity == SIMD3(1000, 0, 0))
        #expect(state.travelled == 0)
        #expect(state.age == 0)
    }

    @Test func aPartialDrawLaunchesSlower() {
        let state = ProjectileFlight.launch(
            from: SIMD3(), along: SIMD3(1, 0, 0), profile: profile, speedScale: 0.35
        )

        #expect(abs(state.velocity.x - 350) < 0.001)
    }

    /// One step is the closed form, not an approximation of it.
    @Test func oneStepMatchesTheClosedForm() {
        let start = ProjectileFlight.launch(
            from: SIMD3(), along: SIMD3(1, 0, 0), profile: profile
        )

        let stepped = ProjectileFlight.step(start, profile: profile, dt: 0.5)

        // x = 1000 * 0.5 = 500; z = -0.5 * 1400 * 0.25 = -175.
        #expect(abs(stepped.position.x - 500) < 0.001)
        #expect(abs(stepped.position.z + 175) < 0.001)
        #expect(abs(stepped.velocity.z + 700) < 0.001)
        #expect(abs(stepped.age - 0.5) < 0.0001)
        // Path length, not displacement along x.
        #expect(stepped.travelled > 500)
    }

    /// The whole trajectory, pinned. A shot fired 45 degrees up at 1000
    /// units/s under 1400 units/s^2 has vertical speed 1000/sqrt(2) = 707.1, so
    /// it apexes at v^2/2a = 500000/2800 = 178.57 units after 0.5051 s and is
    /// back at launch height at twice that.
    @Test func aBallisticArcApexesAndReturnsWhereTheClosedFormSaysItDoes() {
        let launch = ProjectileFlight.launch(
            from: SIMD3(), along: SIMD3(1, 0, 1), profile: profile
        )

        let apex = ProjectileFlight.apexHeight(of: launch, profile: profile)
        #expect(abs(apex - 178.571) < 0.01)

        // Integrated at the runtime's own fixed step, all the way back down.
        var state = launch
        var highest: Float = 0
        var steps = 0
        while state.position.z >= 0, steps < 1000 {
            state = ProjectileFlight.step(
                state, profile: profile, dt: WalkController.fixedTimeStep
            )
            highest = max(highest, state.position.z)
            steps += 1
        }
        // The integrated apex matches the closed form to within one step's
        // worth of curvature, which is the whole claim the exact integrator
        // makes.
        #expect(abs(highest - apex) < 0.02)
        // Time of flight 2 * 0.5051 = 1.0102 s, reached within one fixed step.
        #expect(abs(state.age - 1.0102) < WalkController.fixedTimeStep + 0.001)
        // The horizontal component never accelerates, so x is exactly the
        // horizontal launch speed times the flight time whenever the loop
        // happened to stop.
        let horizontalSpeed = 1000 / 2.0.squareRoot()
        #expect(abs(state.position.x - Float(horizontalSpeed) * state.age) < 0.01)
    }

    /// The determinism the issue asks for: the same shot integrated at two
    /// different step sizes lands in the same place.
    @Test func theTrajectoryDoesNotDependOnHowTheFlightWasSubdivided() {
        let launch = ProjectileFlight.launch(
            from: SIMD3(), along: SIMD3(1, 0, 0.5), profile: profile
        )

        func integrate(dt: Float, steps: Int) -> SIMD3<Float> {
            var state = launch
            for _ in 0 ..< steps {
                state = ProjectileFlight.step(state, profile: profile, dt: dt)
            }
            return state.position
        }

        let coarse = integrate(dt: 1.0 / 60, steps: 60)
        let fine = integrate(dt: 1.0 / 240, steps: 240)

        #expect(simd_distance(coarse, fine) < 0.01)
    }

    @Test func dropAtADistanceIsHalfGTSquared() {
        // 1000 units at 1000 units/s is one second; 0.5 * 1400 * 1 = 700.
        let drop = ProjectileFlight.drop(
            of: profile, atHorizontalDistance: 1000, launchDirection: SIMD3(1, 0, 0)
        )

        #expect(drop != nil)
        #expect(abs((drop ?? 0) - 700) < 0.001)
    }

    @Test func dropIsUnreportableWhenTheShotHasNoHorizontalSpeed() {
        let drop = ProjectileFlight.drop(
            of: profile, atHorizontalDistance: 1000, launchDirection: SIMD3(0, 0, 1)
        )

        #expect(drop == nil)
    }

    @Test func aProfileWithNoGravityFliesStraight() {
        let flat = ProjectileProfile(speed: 1000, gravityFactor: 0)
        let launch = ProjectileFlight.launch(
            from: SIMD3(), along: SIMD3(1, 0, 0), profile: flat
        )

        let stepped = ProjectileFlight.step(launch, profile: flat, dt: 2)

        #expect(stepped.position.z == 0)
        #expect(abs(stepped.position.x - 2000) < 0.001)
        #expect(ProjectileFlight.drop(of: flat, after: 10) == 0)
    }

    @Test func theAimRayIsTiltedUpByTheSettingsAngle() {
        let level = ProjectileFlight.aimDirection(
            cameraForward: SIMD3(1, 0, 0), tiltDegrees: 2.5
        )

        // A 2.5 degree tilt on a level ray puts sin(2.5 degrees) on z.
        #expect(abs(level.z - sinf(2.5 * Float.pi / 180)) < 0.0001)
        #expect(abs(simd_length(level) - 1) < 0.0001)
    }

    @Test func aZeroTiltLeavesTheAimRayAlone() {
        let direction = ProjectileFlight.aimDirection(
            cameraForward: SIMD3(0, 2, 0), tiltDegrees: 0
        )

        #expect(direction == SIMD3(0, 1, 0))
    }

    /// A ray aimed straight up has no horizontal axis to pitch about, and is
    /// left alone rather than producing a NaN heading.
    @Test func aVerticalAimRayIsNotTilted() {
        let direction = ProjectileFlight.aimDirection(
            cameraForward: SIMD3(0, 0, 1), tiltDegrees: 2.5
        )

        #expect(direction == SIMD3(0, 0, 1))
    }

    /// A record carrying a NaN must produce a projectile that goes nowhere,
    /// never one whose position becomes NaN and poisons every query it touches.
    @Test func nonFiniteRecordValuesAreNeutralized() {
        let broken = ProjectileProfile(
            speed: .nan, gravityFactor: -1, range: .infinity, lifetime: .nan
        )

        #expect(broken.speed == 0)
        #expect(broken.gravityFactor == 0)
        #expect(broken.range == 0)
        #expect(broken.lifetime == 0)
        #expect(broken.isFlyable == false)
    }

    @Test func aDegenerateAimDirectionStillProducesAUnitRay() {
        let direction = ProjectileFlight.normalized(SIMD3())

        #expect(direction == SIMD3(1, 0, 0))
    }
}
