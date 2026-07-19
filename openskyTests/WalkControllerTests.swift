// Walk controller math over synthetic terrain only: fixed/clamped stepping,
// gravity/snap, slope rejection, walk/run speeds, streamed-cell seams.

@testable import opensky
import simd
import Testing

struct WalkControllerTests {
    private static let up = SIMD3<Float>(0, 0, 1)

    @Test
    func settlesCapsuleOnGroundAndPlacesCameraAtEyeHeight() {
        var camera = FreeFlyCamera(
            position: SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
        var controller = WalkController(cameraPosition: camera.position)
        controller.update(
            camera: &camera,
            input: CameraInput(dt: WalkController.fixedTimeStep),
            sampleGround: Self.flatGround
        )

        #expect(controller.isGrounded)
        #expect(controller.feetPosition.z == 0)
        #expect(camera.position.z == PlayerCapsule.standard.eyeHeight)
    }

    @Test
    func movementIsHorizontalEvenWhenLookingUp() {
        var camera = Self.camera(pitch: .pi / 3)
        var controller = WalkController(cameraPosition: camera.position)
        Self.settle(&controller, camera: &camera)
        controller.update(
            camera: &camera,
            input: CameraInput(moveForward: 1, dt: 1 / 60),
            sampleGround: Self.flatGround
        )

        #expect(controller.feetPosition.x > 0)
        #expect(abs(controller.feetPosition.z) < 1e-6)
    }

    @Test
    func runSpeedIsTwiceWalkSpeed() {
        var walkCamera = Self.camera()
        var runCamera = Self.camera()
        var walker = WalkController(cameraPosition: walkCamera.position)
        var runner = WalkController(cameraPosition: runCamera.position)
        Self.settle(&walker, camera: &walkCamera)
        Self.settle(&runner, camera: &runCamera)

        walker.update(
            camera: &walkCamera,
            input: CameraInput(moveForward: 1, dt: 0.1),
            sampleGround: Self.flatGround
        )
        runner.update(
            camera: &runCamera,
            input: CameraInput(moveForward: 1, boost: true, dt: 0.1),
            sampleGround: Self.flatGround
        )
        #expect(abs(runner.feetPosition.x / walker.feetPosition.x - 2) < 1e-5)
    }

    @Test
    func steepGroundBlocksGroundedHorizontalMove() {
        var camera = Self.camera()
        var controller = WalkController(cameraPosition: camera.position)
        Self.settle(&controller, camera: &camera)
        let start = controller.feetPosition
        let steep = simd_normalize(SIMD3<Float>(1, 0, 0.5))

        controller.update(
            camera: &camera,
            input: CameraInput(moveForward: 1, dt: 0.1)
        ) { position in
            TerrainGroundSample(height: 0, normal: position.x > 0 ? steep : Self.up)
        }
        #expect(controller.feetPosition.x == start.x)
        #expect(controller.isGrounded)
    }

    @Test
    func frameTimeClampsToOneTenthSecond() {
        var camera = Self.camera()
        var controller = WalkController(cameraPosition: camera.position)
        Self.settle(&controller, camera: &camera)
        controller.update(
            camera: &camera,
            input: CameraInput(moveForward: 1, dt: 10),
            sampleGround: Self.flatGround
        )
        #expect(abs(controller.feetPosition.x - WalkController.walkSpeed * 0.1) < 0.01)
    }

    @Test
    func fixedStepsMatchAcrossFramePartitions() {
        var oneCamera = Self.camera()
        var sixCamera = Self.camera()
        var one = WalkController(cameraPosition: oneCamera.position)
        var six = WalkController(cameraPosition: sixCamera.position)
        Self.settle(&one, camera: &oneCamera)
        Self.settle(&six, camera: &sixCamera)

        one.update(
            camera: &oneCamera,
            input: CameraInput(moveForward: 1, dt: 0.1),
            sampleGround: Self.flatGround
        )
        for _ in 0 ..< 6 {
            six.update(
                camera: &sixCamera,
                input: CameraInput(moveForward: 1, dt: 1 / 60),
                sampleGround: Self.flatGround
            )
        }
        #expect(simd_distance(one.feetPosition, six.feetPosition) < 1e-4)
    }

    @Test
    func gravityFallsWithoutGround() {
        var camera = Self.camera(z: 1000)
        var controller = WalkController(cameraPosition: camera.position)
        controller.update(
            camera: &camera,
            input: CameraInput(dt: 0.1),
            sampleGround: { _ in nil }
        )
        #expect(controller.verticalVelocity < 0)
        #expect(camera.position.z < 1000)
        #expect(!controller.isGrounded)
    }

    @Test
    func crossesThreeResidentCellsWithoutLosingGround() throws {
        var composition = CellSceneComposition()
        for x in 0 ... 3 {
            let coordinate = CellCoordinate(x: Int32(x), y: 0)
            let field = try #require(TerrainHeightFieldTests.field(
                coordinate: coordinate,
                height: 25
            ))
            composition.setCell(
                TerrainHeightFieldTests.cell(field: field),
                at: coordinate
            )
        }
        var camera = FreeFlyCamera(
            position: SIMD3<Float>(64, 2048, 25 + PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
        var controller = WalkController(cameraPosition: camera.position)
        controller.update(
            camera: &camera,
            input: CameraInput(dt: WalkController.fixedTimeStep),
            sampleGround: composition.sampleTerrain
        )
        #expect(controller.isGrounded)

        while camera.position.x < 2.5 * TerrainMeshBuilder.cellSize {
            controller.update(
                camera: &camera,
                input: CameraInput(moveForward: 1, boost: true, dt: 0.1),
                sampleGround: composition.sampleTerrain
            )
            #expect(controller.isGrounded)
            #expect(abs(controller.feetPosition.z - 25) < 1e-5)
        }
        #expect(CellGridManager.cellCoordinate(for: camera.position).x >= 2)
    }

    private static func camera(pitch: Float = 0, z: Float? = nil) -> FreeFlyCamera {
        FreeFlyCamera(
            position: SIMD3<Float>(0, 0, z ?? PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: pitch
        )
    }

    private static func settle(
        _ controller: inout WalkController,
        camera: inout FreeFlyCamera
    ) {
        controller.update(
            camera: &camera,
            input: CameraInput(dt: WalkController.fixedTimeStep),
            sampleGround: flatGround
        )
    }

    private static func flatGround(_: SIMD2<Float>) -> TerrainGroundSample? {
        TerrainGroundSample(height: 0, normal: up)
    }
}
