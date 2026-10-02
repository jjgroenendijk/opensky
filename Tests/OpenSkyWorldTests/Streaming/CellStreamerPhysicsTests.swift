// Dynamic bodies follow cell residency through one reconcile per frame: they
// appear and leave with their cell, survive a rebuild, and reinstall only when
// their scene changed.

@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
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
        streamer.update(cameraPosition: CellStreamerFixture.center)
        runner.complete(coordinate, with: .success(scene))
        streamer.update(cameraPosition: CellStreamerFixture.center)
    }

    @Test
    func aResidentCellInstallsItsBodiesAndAnUnloadedOneDropsThem() {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerFixture.makeStreamer(runner: runner, radius: 0)
        let coordinate = CellStreamerFixture.coordinate(0, 0)
        Self.integrate(
            streamer,
            runner: runner,
            at: coordinate,
            scene: CellStreamerFixture.cellScene(
                location: .exterior(coordinate),
                dynamicBodies: [Self.placement(key: .generated(1))]
            )
        )

        #expect(streamer.dynamicBodies.bodyCount == 1)
        #expect(
            streamer.dynamicBodies.body(for: .generated(1))?.occupiedCell == .exterior(coordinate)
        )

        // Walk far enough that the one-cell grid recenters and drops it.
        streamer.update(
            cameraPosition: CellGridManager.cellCenter(of: CellStreamerFixture.coordinate(9, 9))
        )

        #expect(streamer.dynamicBodies.bodyCount == 0)
    }

    /// A rebuild arrives as a new scene for a cell that never left. The body
    /// keeps the pose it has fallen to rather than being replaced.
    @Test
    func aRebuiltSceneDoesNotResetABodyThatHasAlreadyMoved() {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerFixture.makeStreamer(runner: runner, radius: 0)
        let coordinate = CellStreamerFixture.coordinate(0, 0)
        Self.integrate(
            streamer,
            runner: runner,
            at: coordinate,
            scene: CellStreamerFixture.cellScene(
                location: .exterior(coordinate),
                stateSequence: 1,
                dynamicBodies: [Self.placement(key: .generated(1))]
            )
        )
        for _ in 0 ..< 20 {
            streamer.update(cameraPosition: CellStreamerFixture.center, frameTime: 1.0 / 60)
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
        let streamer = CellStreamerFixture.makeStreamer(runner: runner, radius: 0)
        let coordinate = CellStreamerFixture.coordinate(0, 0)
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
        Self.integrate(
            streamer,
            runner: runner,
            at: coordinate,
            scene: CellStreamerFixture.cellScene(
                location: .exterior(coordinate),
                dynamicBodies: [placement]
            )
        )

        let bounds = ModelBounds(min: SIMD3(-40, -40, 60), max: SIMD3(40, 40, 140))
        #expect(streamer.collisionCandidates(overlapping: bounds).count == 1)
        #expect(streamer.staticCollisionCandidates(overlapping: bounds).isEmpty)
    }
}
