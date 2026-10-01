// Ragdoll stress: one instance collapsed onto collision again and again for
// many simulated minutes without NaN or divergence. It is never rebuilt, so
// joint drift from each collapse carries into the next.

@testable import OpenSkyPhysics
import PhysicsTesting
import simd
import Testing

struct RagdollStabilityTests {
    /// Simulated seconds one collapse gets before the next throw. Long enough
    /// for a fall from `throwHeight` plus a settle.
    private static let secondsPerCollapse: Float = 4
    private static let collapseCount = 60
    private static let throwHeight: Float = 220

    /// Four minutes of simulated time over sixty collapses. At the 1/120 fixed
    /// step that is about 29,000 solver steps.
    @Test
    func survivesRepeatedCollapse() {
        var instance = RagdollFixture.limb()
        let world = RagdollFixture.floorWorld()
        let stepsPerCollapse = Int(Self.secondsPerCollapse / PhysicsStep.fixedTimeStep)
        var worstSeparation: Float = 0
        var worstEnergy: Float = 0

        for collapse in 0 ..< Self.collapseCount {
            throwUpward(&instance, collapse: collapse)
            let ceiling = RagdollFixture.energy(of: instance)
            for _ in 0 ..< stepsPerCollapse {
                instance.step(world: world, dt: PhysicsStep.fixedTimeStep)
                for joint in instance.definition.joints {
                    worstSeparation = max(
                        worstSeparation, RagdollFixture.separation(of: joint, in: instance)
                    )
                }
                worstEnergy = max(worstEnergy, RagdollFixture.energy(of: instance) - ceiling)
            }
            #expect(RagdollFixture.isFinite(instance), "went non-finite on collapse \(collapse)")
            #expect(
                instance.lastStats.recoveredBodyCount == 0,
                "a body needed pose recovery on collapse \(collapse)"
            )
        }

        // Bounded, not zero: a joint stretches while the chain is in the air
        // and the floor is pushing one end of it. What must not happen is the
        // stretch growing collapse after collapse, which is what an unbounded
        // separation would show.
        #expect(
            worstSeparation < RagdollFixture.boneHalfLength,
            "joints stretched to \(worstSeparation) engine units"
        )
        #expect(worstEnergy <= 1, "energy climbed \(worstEnergy) above what a throw put in")
        // Everything ends up on the floor rather than escaping through it or
        // drifting off to infinity.
        for body in instance.bodies {
            #expect(body.position.z > -RagdollFixture.boneHalfLength)
            #expect(body.position.z < Self.throwHeight * 2)
            // Inside the fixture's own floor, which is what makes the "ends up
            // on the floor" assertion above mean anything.
            #expect(simd_length(SIMD2(body.position.x, body.position.y)) < 400)
        }
    }

    /// A ragdoll dropped onto a floor and left alone stays where it settled: a
    /// hundred further steps move it less than a tenth of a unit. A solver that
    /// is quietly fighting itself creeps instead.
    @Test
    func aSettledRagdollStaysPut() {
        var instance = RagdollFixture.limb(origin: SIMD3(0, 0, 40))
        RagdollFixture.run(&instance, world: RagdollFixture.floorWorld(), steps: 2400)
        let settled = instance.bodies.map(\.position)
        RagdollFixture.run(&instance, world: RagdollFixture.floorWorld(), steps: 100)
        for (index, position) in instance.bodies.map(\.position).enumerated() {
            #expect(simd_distance(position, settled[index]) < 0.1)
        }
    }

    /// Throws the ragdoll again without rebuilding it, so the next collapse
    /// inherits the joint state. The direction rotates with the index so each
    /// fall differs.
    private func throwUpward(_ instance: inout RagdollInstance, collapse: Int) {
        let angle = Float(collapse) * 0.7
        let push = SIMD3<Float>(cos(angle) * 260, sin(angle) * 260, 320)
        instance.wake()
        instance.lift(to: Self.throwHeight, velocity: push)
    }
}

extension RagdollInstance {
    /// Test-only re-throw: recentres the chain over the origin with its lowest
    /// bone at `height` and gives every bone one velocity. Recentred because
    /// each throw moves it far past the fixture's floor.
    fileprivate mutating func lift(to height: Float, velocity: SIMD3<Float>) {
        let lowest = bodies.map(\.position.z).min() ?? 0
        let centre = bodies.reduce(SIMD3<Float>.zero) { $0 + $1.position }
            / Float(max(bodies.count, 1))
        let shift = SIMD3<Float>(-centre.x, -centre.y, height - lowest)
        for index in bodies.indices {
            bodies[index].position += shift
            bodies[index].linearVelocity = velocity
            bodies[index].angularVelocity = .zero
        }
    }
}
