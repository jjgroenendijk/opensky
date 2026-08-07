// The deterministic half of item 15.6's acceptance (issue #197): limits hold
// under gravity, the solver converges, energy does not grow, and two identical
// runs match exactly.
//
// Every fixture is built in code by `RagdollFixture`. Nothing here reads the
// install, so the whole suite runs in `make test`.

@testable import opensky
import simd
import Testing

struct RagdollConstraintSolverTests {
    /// Tolerance on a joint's anchor separation, in engine units. Larger than
    /// the solver's own `positionSlop` because a chain under gravity carries a
    /// little stretch through the links above it, and smaller than a tenth of a
    /// bone, so a joint that had actually come apart could not pass.
    private static let separationTolerance: Float = 1.0

    @Test
    func holdsAPointConstraintTogetherUnderGravity() {
        var instance = RagdollFixture.pair()
        RagdollFixture.run(&instance, world: RagdollFixture.emptyWorld, steps: 600)
        let joint = instance.definition.joints[0]
        #expect(RagdollFixture.isFinite(instance))
        #expect(
            RagdollFixture.separation(of: joint, in: instance) < Self.separationTolerance,
            "the two bones came apart"
        )
    }

    /// A free-falling jointed pair still falls: the constraint holds the bones
    /// to each other, not to the world.
    @Test
    func aJointedPairStillFalls() {
        var instance = RagdollFixture.pair()
        let start = instance.bodies[0].position.z
        RagdollFixture.run(&instance, world: RagdollFixture.emptyWorld, steps: 120)
        #expect(instance.bodies[0].position.z < start - 100)
    }

    /// The cone bounds the angle between the two bones for the whole run, not
    /// just at the end. A limit that is only satisfied once the chain settles is
    /// a limit that was violated on the way there.
    @Test
    func aConeHoldsItsAngleThroughout() {
        let coneMax: Float = .pi / 6
        var instance = RagdollFixture.limb(coneMaxAngle: coneMax)
        let hip = instance.definition.joints[0]
        var worst: Float = 0
        for _ in 0 ..< 900 {
            instance.step(world: RagdollFixture.floorWorld(), dt: WalkController.fixedTimeStep)
            worst = max(worst, RagdollFixture.coneAngle(of: hip, in: instance))
        }
        #expect(RagdollFixture.isFinite(instance))
        // The allowance is the overshoot a velocity-level limit permits within
        // one substep before its restoring impulse lands. A limit that was not
        // being solved at all opens to the full half-turn the bones can reach.
        #expect(worst < coneMax + 0.35, "cone opened to \(worst) against a limit of \(coneMax)")
    }

    /// The counterpart to the test above, and the reason it means anything: the
    /// same chain with the hip left as a plain point constraint *does* fold past
    /// the angle the cone would have held it to. Without this, a cone assertion
    /// would pass just as well against a solver that never enforced one.
    @Test
    func withoutAConeTheSameChainFoldsPastIt() {
        let coneMax: Float = .pi / 6
        var instance = RagdollFixture.limb(coneMaxAngle: coneMax, hipLimits: .point)
        let hip = instance.definition.joints[0]
        var worst: Float = 0
        for _ in 0 ..< 900 {
            instance.step(world: RagdollFixture.floorWorld(), dt: WalkController.fixedTimeStep)
            worst = max(worst, RagdollFixture.coneAngle(of: hip, in: instance))
        }
        #expect(worst > coneMax + 0.35, "an unconstrained hip only reached \(worst)")
    }

    /// The solver converges: after enough steps of a collapse there is no
    /// violated limit left.
    @Test
    func theSolverConverges() {
        var instance = RagdollFixture.limb()
        RagdollFixture.run(&instance, world: RagdollFixture.floorWorld(), steps: 1200)
        #expect(instance.lastStats.jointViolationCount == 0)
        #expect(instance.lastStats.recoveredBodyCount == 0)
        for joint in instance.definition.joints {
            #expect(
                RagdollFixture.separation(of: joint, in: instance) < Self.separationTolerance
            )
        }
    }

    /// Energy never climbs above what the ragdoll started with. This is the
    /// property that fails first when a constraint solver is unstable, long
    /// before anything reaches a NaN.
    @Test
    func energyNeverGrows() {
        var instance = RagdollFixture.limb()
        let start = RagdollFixture.energy(of: instance)
        var worst = start
        for _ in 0 ..< 1800 {
            instance.step(world: RagdollFixture.floorWorld(), dt: WalkController.fixedTimeStep)
            worst = max(worst, RagdollFixture.energy(of: instance))
        }
        #expect(worst <= start * 1.05, "energy climbed from \(start) to \(worst)")
    }

    /// Two runs of the same fixture produce bit-identical poses. The engine's
    /// determinism rule reaches the joint solver.
    @Test
    func twoIdenticalRunsMatchExactly() {
        var first = RagdollFixture.limb()
        var second = RagdollFixture.limb()
        RagdollFixture.run(&first, world: RagdollFixture.floorWorld(), steps: 600)
        RagdollFixture.run(&second, world: RagdollFixture.floorWorld(), steps: 600)
        #expect(RagdollFixture.trace(first) == RagdollFixture.trace(second))
    }

    /// A jointed pair generates no contact between its own two bones, which is
    /// what stops two overlapping capsules from spending every step shoving each
    /// other apart against the joint holding them together.
    @Test
    func jointedBonesDoNotContactEachOther() {
        var instance = RagdollFixture.pair()
        // The two capsules overlap by construction: their shared anchor is
        // inside both. Without the filter this run reports contacts every step.
        RagdollFixture.run(&instance, world: RagdollFixture.emptyWorld, steps: 60)
        #expect(instance.lastStats.contactCount == 0)
    }

    /// A ragdoll left alone on a floor eventually sleeps, so a corpse stops
    /// costing solver time and its resting pose can be recorded.
    @Test
    func aSettledRagdollSleeps() {
        var instance = RagdollFixture.limb(origin: SIMD3(0, 0, 20))
        RagdollFixture.run(&instance, world: RagdollFixture.floorWorld(), steps: 2400)
        #expect(instance.isSettled)
        #expect(instance.phase == .settled)
    }

    /// A degenerate joint — one whose bodies do not exist — is skipped rather
    /// than crashing or writing a NaN.
    @Test
    func anUnresolvableJointIsSkipped() {
        var instance = RagdollFixture.pair()
        let bogus = RagdollFixture.joint(bodyA: 0, bodyB: 7, limits: .point)
        var bodies = instance.bodies
        RagdollConstraintSolver.solve(
            joints: [bogus], bodies: &bodies, dt: WalkController.fixedTimeStep
        )
        let finite = bodies.allSatisfy(\.position.isFiniteVector)
        #expect(finite)
        instance.step(world: RagdollFixture.emptyWorld, dt: WalkController.fixedTimeStep)
        #expect(RagdollFixture.isFinite(instance))
    }

    /// A zero or non-finite step does nothing rather than dividing by it.
    @Test
    func aDegenerateStepIsRefused() {
        var bodies = RagdollFixture.pair().bodies
        let before = bodies.map(\.position)
        let joints = RagdollFixture.pair().definition.joints
        RagdollConstraintSolver.solve(joints: joints, bodies: &bodies, dt: 0)
        RagdollConstraintSolver.solve(joints: joints, bodies: &bodies, dt: .nan)
        #expect(bodies.map(\.position) == before)
    }
}
