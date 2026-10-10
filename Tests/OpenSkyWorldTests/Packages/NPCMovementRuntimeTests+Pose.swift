// Which way a mover is drawn: the published heading follows the placement rule.

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
}
