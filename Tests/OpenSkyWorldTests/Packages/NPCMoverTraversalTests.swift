// A walking actor jumps across a navmesh ledge link and swims in deep water.

@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

@MainActor
struct NPCMoverTraversalTests {
    private static let actor = ReferenceKey.plugin(name: "movement.esm", objectID: 1)

    private static func mover(path: NavigationPath) -> NPCMover {
        NPCMover(start: NPCMoveStart(
            actor: actor, formID: FormID(1),
            placement: PlacedReference.Placement(position: .zero, rotation: .zero),
            scale: 1, capsule: .standard, configuration: .synthetic, path: path
        ))
    }

    @Test func arcPeaksAboveTheHigherEndAndLands() {
        var hop = NPCLedgeHop(from: .zero, landing: SIMD3(100, 0, 64), speed: 200)
        hop.advance(by: hop.duration / 2)
        #expect(hop.feetPosition.z > 64)
        hop.advance(by: hop.duration)
        #expect(hop.isFinished)
        #expect(hop.feetPosition == SIMD3(100, 0, 64))
    }

    @Test func moverDropsDownALedgeAndWalksOn() {
        var path = NPCMovementRuntimeTests.path(
            waypoints: [SIMD3(50, 0, 0), SIMD3(80, 0, -100), SIMD3(150, 0, -100)],
            target: SIMD3(150, 0, -100)
        )
        path.ledgeCrossings = [NavigationLedgeCrossing(waypointIndex: 0)]
        var mover = Self.mover(path: path)
        var world = NPCMovementRuntimeTests.world()
        world = NPCMovementWorld(
            sampleGround: { position in
                TerrainGroundSample(height: position.x < 65 ? 0 : -100, normal: SIMD3(0, 0, 1))
            },
            collisionQuery: world.collisionQuery, repath: world.repath,
            cellAt: world.cellAt, triggersAt: world.triggersAt
        )
        var hopped = false
        for _ in 0 ..< 200 where mover.state == .moving {
            _ = mover.advance(by: 0.05, world: world)
            hopped = hopped || mover.hop != nil
        }
        #expect(hopped)
        #expect(mover.state == .arrived)
        #expect(abs(mover.controller.feetPosition.z + 100) < 2)
    }

    @Test func moverSwimsInDeepWater() {
        let path = NPCMovementRuntimeTests.path(
            waypoints: [SIMD3(400, 0, 0)], target: SIMD3(400, 0, 0)
        )
        var mover = Self.mover(path: path)
        var world = NPCMovementRuntimeTests.world()
        world.sampleWater = { _ in 200 }
        _ = mover.advance(by: 0.05, world: world)
        #expect(mover.isSwimming)
        _ = mover.advance(by: 0.05, world: world)
        #expect(mover.gait == .swim)
    }

    @Test func moverWadesInShallowWater() {
        let path = NPCMovementRuntimeTests.path(
            waypoints: [SIMD3(400, 0, 0)], target: SIMD3(400, 0, 0)
        )
        var mover = Self.mover(path: path)
        var world = NPCMovementRuntimeTests.world()
        world.sampleWater = { _ in 40 }
        _ = mover.advance(by: 0.05, world: world)
        #expect(!mover.isSwimming)
        #expect(mover.gait != .swim)
    }
}
