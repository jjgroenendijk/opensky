// The acceptance behaviour of the dynamic solver (issue #193): a dropped box
// settles and sleeps, an impulse wakes it, and a crowded scene stays finite,
// stays above the floor, and produces the same resting state twice.

@testable import opensky
import simd
import Testing

struct DynamicBodySolverTests {
    @Test
    func droppedBoxSettlesOnTheFloorAndSleeps() {
        let world = DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor()])
        )
        var bodies = [DynamicBodyScene.cube(key: .generated(1), center: SIMD3(0, 0, 120))]

        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 400)

        let body = bodies[0]
        #expect(body.isSleeping)
        // The box half-extent is 10, so a resting centre sits a little above
        // 10: the solver leaves `penetrationSlop` of overlap unresolved and the
        // contact margin holds it off by a fraction more.
        #expect(body.position.z > 9)
        #expect(body.position.z < 13)
        #expect(simd_length(body.linearVelocity) == 0)
    }

    @Test
    func impulseWakesASettledBody() {
        let world = DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor()])
        )
        var bodies = [DynamicBodyScene.cube(key: .generated(1), center: SIMD3(0, 0, 40))]
        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 400)
        #expect(bodies[0].isSleeping)
        let restingX = bodies[0].position.x

        bodies[0].applyImpulse(SIMD3(4000, 0, 0), at: bodies[0].position)
        #expect(!bodies[0].isSleeping)
        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 60)

        #expect(bodies[0].position.x > restingX + 5)
    }

    @Test
    func aSleepingBodyStopsMovingEntirely() {
        let world = DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor()])
        )
        var bodies = [DynamicBodyScene.cube(key: .generated(1), center: SIMD3(0, 0, 30))]
        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 400)
        let settled = bodies[0].position

        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 600)

        #expect(bodies[0].isSleeping)
        #expect(simd_distance(bodies[0].position, settled) == 0)
    }

    @Test
    func aFastBodyIsStoppedByAWallRatherThanTunnelingThrough() {
        let world = DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([
                DynamicBodyScene.floor(), DynamicBodyScene.wall(at: 100)
            ])
        )
        var bodies = [DynamicBodyScene.cube(key: .generated(1), center: SIMD3(-100, 0, 40))]
        // Far faster than a fall or a shove: one unguarded step at this speed
        // would put the box on the other side of the wall.
        bodies[0].linearVelocity = SIMD3(6000, 0, 0)

        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 240)

        #expect(bodies[0].position.x < 100)
        #expect(bodies[0].position.isFiniteVector)
    }

    /// The stress acceptance: dozens of bodies, a long run, no NaN, nothing
    /// through the floor, and the same resting state from the same inputs.
    @Test
    func aCrowdedSceneSettlesFiniteAndReproducibly() {
        let first = Self.runStressScene()
        let second = Self.runStressScene()

        #expect(first.count == 36)
        for body in first {
            #expect(body.position.isFiniteVector)
            #expect(body.orientation.vector.isFiniteVector4)
            #expect(body.position.z > 0, "body fell through the floor")
            #expect(body.position.z < 400)
        }
        for (left, right) in zip(first, second) {
            #expect(left.key == right.key)
            #expect(left.position == right.position)
            #expect(left.orientation.vector == right.orientation.vector)
            #expect(left.isSleeping == right.isSleeping)
        }
    }

    @Test
    func aShovedBodyPushesTheOneBesideIt() {
        let world = DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor()])
        )
        var bodies = [
            DynamicBodyScene.cube(key: .generated(1), center: SIMD3(-30, 0, 11)),
            DynamicBodyScene.cube(key: .generated(2), center: SIMD3(0, 0, 11))
        ]
        let restingX = bodies[1].position.x
        bodies[0].applyImpulse(SIMD3(20000, 0, 0), at: bodies[0].position)

        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 180)

        #expect(bodies[1].position.x > restingX + 1)
        // Bound outside the macro: `allSatisfy` is `rethrows`, and the
        // expectation macro cannot see that this call site does not throw.
        let finite = bodies.allSatisfy(\.position.isFiniteVector)
        #expect(finite)
    }

    /// Vanilla authors clutter slightly inside the shelf it stands on, which the
    /// real-data probe found is the common case rather than the exception. A body
    /// that starts embedded has to be expelled onto the surface, not through it.
    @Test
    func aBodyStartingInsideAShelfIsPushedOutOntoIt() {
        let shelf = StaticCollisionShape(
            reference: FormID(2),
            transform: MatrixMath.translation(SIMD3(0, 0, 100)),
            geometry: .box(halfExtents: SIMD3(200, 200, 8)),
            bounds: ModelBounds(min: SIMD3(-200, -200, 92), max: SIMD3(200, 200, 108))
        )
        let world = DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor(), shelf])
        )
        // Bottom at 105, three units inside the board's top face at 108 and
        // thirteen above its underside — the way vanilla authors clutter, and
        // the case the nearest-surface rule has to read as "climb out upward".
        var bodies = [DynamicBodyScene.cube(key: .generated(1), center: SIMD3(0, 0, 115))]

        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 600)

        #expect(bodies[0].position.z > 108, "the body sank through the shelf")
        #expect(bodies[0].isSleeping)
    }

    /// Six by six boxes dropped from staggered heights onto a floor, run long
    /// enough to settle and then some.
    private static func runStressScene() -> [DynamicBody] {
        let world = DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor()])
        )
        var bodies: [DynamicBody] = []
        for row in 0 ..< 6 {
            for column in 0 ..< 6 {
                let index = row * 6 + column
                bodies.append(DynamicBodyScene.cube(
                    key: .generated(UInt64(index + 1)),
                    center: SIMD3(
                        Float(column) * 24 - 60,
                        Float(row) * 24 - 60,
                        60 + Float(index % 5) * 18
                    ),
                    mass: 12 + Float(index % 4) * 6
                ))
            }
        }
        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 600)
        return bodies
    }
}
