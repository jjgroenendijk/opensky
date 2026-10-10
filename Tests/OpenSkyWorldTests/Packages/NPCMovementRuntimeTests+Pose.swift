// Where a mover stands and which way it is drawn: the published heading, and the
// static floor under a marker walk.

@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
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
