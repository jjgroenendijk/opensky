// Dynamic bodies following cell residency (issue #193). The streamer does not
// push placements at the physics world; it reconciles once per frame, so these
// cover what that reconciliation has to get right: bodies appear with their
// cell, leave with it, survive a rebuild, and only re-install when the scene
// they came from actually changed.

@testable import opensky
import simd
import Testing

@MainActor
struct CellStreamerPhysicsTests {
    private static func placement(key: ReferenceKey) -> DynamicBodyPlacement {
        let volume = DynamicCollisionVolume.box(halfExtents: SIMD3(repeating: 10))
            ?? .radial(first: .zero, second: .zero, radius: 10)
        return DynamicBodyPlacement(
            key: key,
            reference: FormID(0x200),
            definition: DynamicBodyDefinition(volumes: [volume], mass: 20),
            originPosition: SIMD3(0, 0, 100),
            orientation: .identityRotation
        )
    }

    private static func integrate(
        _ streamer: CellStreamer,
        runner: ManualCellBuildRunner,
        at coordinate: CellCoordinate,
        scene: CellScene
    ) {
        streamer.update(cameraPosition: CellStreamerTests.center)
        runner.complete(coordinate, with: .success(scene))
        streamer.update(cameraPosition: CellStreamerTests.center)
    }

    @Test
    func aResidentCellInstallsItsBodiesAndAnUnloadedOneDropsThem() {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        let coordinate = CellStreamerTests.coordinate(0, 0)
        Self.integrate(streamer, runner: runner, at: coordinate, scene: CellStreamerTests.cellScene(
            location: .exterior(coordinate),
            dynamicBodies: [Self.placement(key: .generated(1))]
        ))

        #expect(streamer.dynamicBodies.bodyCount == 1)
        #expect(streamer.dynamicBodies.body(for: .generated(1))?.cell == .exterior(coordinate))

        // Walk far enough that the one-cell grid recenters and drops it.
        streamer.update(
            cameraPosition: CellGridManager.cellCenter(of: CellStreamerTests.coordinate(9, 9))
        )

        #expect(streamer.dynamicBodies.bodyCount == 0)
    }

    /// A rebuild arrives as a new scene for a cell that never left. The body
    /// keeps the pose it has fallen to rather than being replaced.
    @Test
    func aRebuiltSceneDoesNotResetABodyThatHasAlreadyMoved() {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        let coordinate = CellStreamerTests.coordinate(0, 0)
        Self.integrate(streamer, runner: runner, at: coordinate, scene: CellStreamerTests.cellScene(
            location: .exterior(coordinate),
            stateSequence: 1,
            dynamicBodies: [Self.placement(key: .generated(1))]
        ))
        for _ in 0 ..< 20 {
            streamer.update(cameraPosition: CellStreamerTests.center, frameTime: 1.0 / 60)
        }
        let fallen = streamer.dynamicBodies.body(for: .generated(1))?.position.z ?? 0
        #expect(fallen < 100)

        streamer.dynamicBodies.setCell(
            .exterior(coordinate),
            placements: [Self.placement(key: .generated(1))],
            sequence: 2
        )

        #expect(streamer.dynamicBodies.body(for: .generated(1))?.position.z == fallen)
    }

    /// A moving body is visible to the ordinary collision query, and the solver
    /// is handed only the static half so a body is never its own obstacle.
    @Test
    func theCollisionQueryUnionsStaticShapesWithMovingBodies() {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        let coordinate = CellStreamerTests.coordinate(0, 0)
        let volume = DynamicCollisionVolume.box(halfExtents: SIMD3(repeating: 10))
            ?? .radial(first: .zero, second: .zero, radius: 10)
        let placement = DynamicBodyPlacement(
            key: .generated(1),
            reference: FormID(0x321),
            definition: DynamicBodyDefinition(
                volumes: [volume],
                mass: 20,
                colliderShapes: [DynamicBodyColliderShape(
                    transform: matrix_identity_float4x4,
                    geometry: .box(halfExtents: SIMD3(repeating: 10)),
                    material: nil
                )]
            ),
            originPosition: SIMD3(0, 0, 100),
            orientation: .identityRotation
        )
        Self.integrate(streamer, runner: runner, at: coordinate, scene: CellStreamerTests.cellScene(
            location: .exterior(coordinate),
            dynamicBodies: [placement]
        ))

        let bounds = ModelBounds(min: SIMD3(-40, -40, 60), max: SIMD3(40, 40, 140))
        #expect(streamer.collisionCandidates(overlapping: bounds).count == 1)
        #expect(streamer.staticCollisionCandidates(overlapping: bounds).isEmpty)
    }
}
