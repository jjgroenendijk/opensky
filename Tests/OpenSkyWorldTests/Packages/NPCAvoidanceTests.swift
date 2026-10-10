// Local steering between walkers: passing a neighbour ahead, separating an overlap,
// and counting a taken marker as reached.

@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
import simd
import Testing

@MainActor
struct NPCAvoidanceTests {
    private static let other = ReferenceKey.plugin(name: "movement.esm", objectID: 9)

    private static func neighbour(_ x: Float, _ y: Float) -> NPCNeighbour {
        NPCNeighbour(key: other, position: SIMD2(x, y), radius: 20)
    }

    @Test func nothingInTheWayLeavesTheDirection() {
        let steered = NPCAvoidance.steer(
            direction: SIMD2(2, 0), from: .zero, radius: 20, neighbours: [Self.neighbour(-80, 0)]
        )
        #expect(steered == SIMD2(1, 0))
    }

    @Test func aNeighbourDeadAheadIsPassedOnTheRight() {
        let steered = NPCAvoidance.steer(
            direction: SIMD2(1, 0), from: .zero, radius: 20, neighbours: [Self.neighbour(80, 0)]
        )
        #expect(steered.x > 0)
        #expect(steered.y < 0, "walking +X, the right side is -Y")
    }

    @Test func aNeighbourAheadOnTheRightTurnsTheWalkLeft() {
        let steered = NPCAvoidance.steer(
            direction: SIMD2(1, 0), from: .zero, radius: 20, neighbours: [Self.neighbour(80, -10)]
        )
        #expect(steered.y > 0)
    }

    @Test func overlappingActorsArePushedApart() {
        let steered = NPCAvoidance.steer(
            direction: SIMD2(0, 1), from: .zero, radius: 20, neighbours: [Self.neighbour(10, 0)]
        )
        #expect(steered.x < 0)
    }

    @Test func aMarkerTakenByANeighbourCountsAsReached() {
        let marker = SIMD2<Float>(100, 0)
        #expect(NPCAvoidance.isTaken(
            marker, from: SIMD2(52, 0), radius: 20, tolerance: 12,
            neighbours: [Self.neighbour(100, 0)]
        ))
        #expect(!NPCAvoidance.isTaken(
            marker, from: SIMD2(0, 0), radius: 20, tolerance: 12,
            neighbours: [Self.neighbour(100, 0)]
        ))
    }

    /// Two actors walking at each other along one line pass without overlapping.
    @Test func twoWalkersHeadOnPassEachOther() {
        let west = ReferenceKey.plugin(name: "movement.esm", objectID: 1)
        let east = ReferenceKey.plugin(name: "movement.esm", objectID: 2)
        var runtime = NPCMovementRuntime()
        for (key, from, to) in [(west, Float(0), Float(400)), (east, Float(400), Float(0))] {
            let path = NPCMovementRuntimeTests.path(
                waypoints: [SIMD3(to, 0, 0)], target: SIMD3(to, 0, 0)
            )
            let started = runtime.start(NPCMoveStart(
                actor: key, formID: FormID(key == west ? 1 : 2),
                placement: PlacedReference.Placement(position: SIMD3(from, 0, 0), rotation: .zero),
                scale: 1, capsule: .standard, configuration: .synthetic, path: path
            ))
            #expect(started)
        }
        var closest = Float.greatestFiniteMagnitude
        for _ in 0 ..< 200 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 0.05, world: NPCMovementRuntimeTests.world())
            let feet = runtime.readouts().map(\.feetPosition)
            if feet.count == 2 {
                let gap = simd_distance(SIMD2(feet[0].x, feet[0].y), SIMD2(feet[1].x, feet[1].y))
                closest = min(closest, gap)
            }
        }
        #expect(runtime.readouts().allSatisfy { $0.state == .arrived })
        #expect(closest >= PlayerCapsule.standard.radius * 2)
    }
}
