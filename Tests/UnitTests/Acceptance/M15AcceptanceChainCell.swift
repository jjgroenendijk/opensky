// The M15 gate's cell and spawn half (issue #198), in a satellite of
// `M15AcceptanceChain.swift` beside the input half, for the strict-lint
// type-length cap.
//
// The scene here is the arena: a floor, a wall an arrow can stick in, and one
// crate of movable clutter. It is handed to the real `CellStreamer` through the
// shared `ManualCellBuildRunner`, so residency, the shove, the solver step and
// the settled-pose drain are all the engine's own.

@testable import opensky
import simd

@MainActor
extension M15AcceptanceChain {
    // MARK: - Spawning

    /// A fresh key for a stuck arrow, in the same generated space the world
    /// state store hands out.
    func nextSpawnKey() -> ReferenceKey {
        nextSpawnSequence += 1
        return .generated(nextSpawnSequence)
    }

    // MARK: - The cell

    /// Completes every cell build the streamer asked for, with the arena's
    /// floor, wall and one crate of clutter.
    func completePendingBuilds() {
        let pending = runner.enqueued.suffix(from: min(completedBuilds, runner.enqueued.count))
        for coordinate in pending {
            completedBuilds += 1
            runner.complete(coordinate, with: .success(Self.scene(coordinate)))
        }
        guard !pending.isEmpty else { return }
        streamer.update(cameraPosition: controller.cameraPosition)
    }

    static func scene(_ coordinate: CellCoordinate) -> CellScene {
        CellStreamerTests.cellScene(
            location: .exterior(coordinate),
            staticCollision: StaticCollisionSet(
                location: .exterior(coordinate),
                shapes: M15AcceptanceWorld.collisionShapes(),
                stats: StaticCollisionStats()
            ),
            dynamicBodies: coordinate == Self.coordinate
                ? [M15AcceptanceWorld.clutter(
                    key: crate, x: M15AcceptanceWorld.startX + 90
                )]
                : []
        )
    }
}
