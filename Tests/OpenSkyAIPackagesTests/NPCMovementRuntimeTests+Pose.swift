// Where a mover stands and which way it is drawn: the published heading, and the
// static floor under a marker walk.

@testable import OpenSkyAIPackages
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
import OpenSkyNavigation
@testable import OpenSkyPhysics
@testable import OpenSkyWorldState
import simd
import Testing

extension NPCMovementRuntimeTests {
    /// A placement's `angleZ` is clockwise from north, so an actor walking east
    /// is drawn at a quarter turn and one turning north at zero.
    @Test
    func publishedHeadingFacesTheWayTheActorMoves() throws {
        var runtime = NPCMovementRuntime()
        let started = runtime.start(Self.start(
            actor: actor,
            path: Self.path(waypoints: [SIMD3(2000, 0, 0)], target: SIMD3(2000, 0, 0))
        ))
        #expect(started)
        for _ in 0 ..< 60 {
            runtime.advance(by: 1 / 60, world: Self.world())
        }
        let walking = try #require(runtime.transform(for: actor))
        #expect(abs(walking.rotation.z - .pi / 2) < 0.01)

        runtime.face(Self.face(
            actor: actor, target: walking.position + SIMD3(0, 2000, 0)
        ))
        for _ in 0 ..< 120 {
            runtime.advance(by: 1 / 60, world: Self.world())
        }
        let facing = try #require(runtime.transform(for: actor))
        #expect(abs(facing.rotation.z) < 0.01)
    }

    /// A marker walk ignores walls but stands on a road laid over the terrain.
    @Test
    func aMarkerWalkStandsOnARoadAboveTheTerrain() throws {
        var start = Self.start(actor: actor, path: .straight(to: SIMD3(100, 0, 0)))
        start.ignoresStatics = true
        var runtime = NPCMovementRuntime()
        let started = runtime.start(start)
        #expect(started)

        let paved = Self.world(collisionQuery: { _ in [Self.road] })
        for _ in 0 ..< 100 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 0.1, world: paved)
        }

        let readout = try #require(runtime.readouts().first)
        #expect(readout.feetPosition.x > 80)
        #expect(abs(readout.feetPosition.z - 10) < 0.5)
    }

    /// Ledges that rise a step at a time, as inside a rock the leg passes through,
    /// do not lift a marker walk off its line.
    @Test
    func aMarkerWalkDoesNotClimbLedgesAboveItsLine() throws {
        var start = Self.start(actor: actor, path: .straight(to: SIMD3(220, 0, 0)))
        start.ignoresStatics = true
        var runtime = NPCMovementRuntime()
        let started = runtime.start(start)
        #expect(started)

        let ledges = Self.world(collisionQuery: { _ in Self.ledges })
        for _ in 0 ..< 100 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 0.1, world: ledges)
        }

        let readout = try #require(runtime.readouts().first)
        #expect(readout.feetPosition.x > 200)
        #expect(readout.feetPosition.z < 33)
    }

    /// Ten ledges 20 units apart, each 20 units higher than the one before.
    private static let ledges = (1 ... 10).map { index in
        let top = Float(index) * 20
        let center = SIMD3<Float>(Float(index) * 20, 0, top - 10)
        return StaticCollisionShape(
            reference: FormID(0x910 + UInt32(index)),
            transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: SIMD3(10, 200, 10)),
            bounds: ModelBounds(
                min: center - SIMD3(10, 200, 10), max: center + SIMD3(10, 200, 10)
            )
        )
    }

    /// A road slab whose top is at z = 10.
    private static let road = StaticCollisionShape(
        reference: FormID(0x901),
        transform: MatrixMath.translation(SIMD3(50, 0, 0)),
        geometry: .box(halfExtents: SIMD3(200, 200, 10)),
        bounds: ModelBounds(
            min: SIMD3(-150, -200, -10),
            max: SIMD3(250, 200, 10)
        )
    )
}
