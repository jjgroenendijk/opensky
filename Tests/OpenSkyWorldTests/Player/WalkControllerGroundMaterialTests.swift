// The ground contact reports the material under the player's feet. Each
// collision shape carries a material, and the footstep chain reads it.

@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import PhysicsTesting
import simd
import Testing

struct WalkControllerGroundMaterialTests {
    private static let wood = FormID(0x101)
    private static let stone = FormID(0x102)
    private static let snow = FormID(0x103)

    @Test func standingOnAMeshReportsThatMeshsMaterial() {
        var camera = Self.camera(feet: SIMD3(0, 0, 40))
        var controller = WalkController(cameraPosition: camera.position)
        let query = DynamicBodyScene.candidateQuery([DynamicBodyScene.floor(
            extent: 200,
            material: Self.wood
        )])

        Self.settle(&controller, camera: &camera, query: query)

        #expect(controller.isGrounded)
        #expect(controller.groundMaterial == Self.wood)
    }

    @Test func fallingReportsNoMaterialAtAll() {
        var camera = Self.camera(feet: SIMD3(0, 0, 4000))
        var controller = WalkController(cameraPosition: camera.position)
        let query = DynamicBodyScene.candidateQuery([DynamicBodyScene.floor(
            extent: 200,
            material: Self.wood
        )])

        controller.update(
            camera: &camera,
            input: CameraInput(dt: WalkController.fixedTimeStep),
            sampleGround: { _ in nil },
            collisionQuery: query
        )

        #expect(!controller.isGrounded)
        #expect(controller.groundMaterial == nil)
    }

    @Test func terrainReportsTheMaterialTheGroundSamplerNames() {
        var camera = Self.camera(feet: SIMD3(0, 0, 10))
        var controller = WalkController(cameraPosition: camera.position)
        let ground: WalkController.GroundSampler = { _ in
            TerrainGroundSample(height: 0, normal: SIMD3(0, 0, 1), material: Self.snow)
        }

        for _ in 0 ..< 240 {
            controller.update(
                camera: &camera,
                input: CameraInput(dt: WalkController.fixedTimeStep),
                sampleGround: ground
            )
        }

        #expect(controller.isGrounded)
        #expect(controller.groundMaterial == Self.snow)
    }

    /// Terrain and a mesh can both touch the capsule on a seam. The one that
    /// put the feet down is the landscape, so that is the surface reported.
    @Test func terrainWinsOverAMeshItIsRestingAgainst() {
        var camera = Self.camera(feet: SIMD3(0, 0, 10))
        var controller = WalkController(cameraPosition: camera.position)
        let query = DynamicBodyScene.candidateQuery([DynamicBodyScene.floor(
            extent: 200,
            material: Self.wood
        )])
        let ground: WalkController.GroundSampler = { _ in
            TerrainGroundSample(height: 0, normal: SIMD3(0, 0, 1), material: Self.snow)
        }

        for _ in 0 ..< 240 {
            controller.update(
                camera: &camera,
                input: CameraInput(dt: WalkController.fixedTimeStep),
                sampleGround: ground,
                collisionQuery: query
            )
        }

        #expect(controller.groundMaterial == Self.snow)
    }

    /// A wall the capsule is pressed against is not what it stands on, so its
    /// material must not be the one reported.
    @Test func aWallBesideTheFeetDoesNotDecideTheMaterial() {
        var camera = Self.camera(feet: SIMD3(0, 0, 40))
        var controller = WalkController(cameraPosition: camera.position)
        let wall = DynamicBodyScene.quad(
            SIMD3(20, -100, -10), SIMD3(20, 100, -10),
            SIMD3(20, 100, 200), SIMD3(20, -100, 200),
            material: Self.stone
        )
        let query = DynamicBodyScene.candidateQuery([
            DynamicBodyScene.floor(extent: 200, material: Self.wood),
            wall
        ])

        Self.settle(&controller, camera: &camera, query: query, moveForward: 1)

        #expect(controller.isGrounded)
        #expect(controller.groundMaterial == Self.wood)
    }

    @Test func aSurfaceWithNoMaterialReportsNone() {
        var camera = Self.camera(feet: SIMD3(0, 0, 40))
        var controller = WalkController(cameraPosition: camera.position)
        let query = DynamicBodyScene.candidateQuery([DynamicBodyScene.floor(
            extent: 200,
            material: nil
        )])

        Self.settle(&controller, camera: &camera, query: query)

        #expect(controller.isGrounded)
        #expect(controller.groundMaterial == nil)
    }

    @Test func resetForgetsTheSurface() {
        var camera = Self.camera(feet: SIMD3(0, 0, 40))
        var controller = WalkController(cameraPosition: camera.position)
        Self.settle(&controller, camera: &camera, query: DynamicBodyScene.candidateQuery([
            DynamicBodyScene.floor(extent: 200, material: Self.wood)
        ]))

        controller.reset(cameraPosition: camera.position)

        #expect(controller.groundMaterial == nil)
    }

    // MARK: - Fixtures

    private static func settle(
        _ controller: inout WalkController,
        camera: inout FreeFlyCamera,
        query: @escaping WalkController.CollisionQuery,
        moveForward: Float = 0
    ) {
        for _ in 0 ..< 120 {
            controller.update(
                camera: &camera,
                input: CameraInput(
                    moveForward: moveForward,
                    dt: WalkController.fixedTimeStep
                ),
                sampleGround: { _ in nil },
                collisionQuery: query
            )
        }
    }

    private static func camera(feet: SIMD3<Float>) -> FreeFlyCamera {
        FreeFlyCamera(
            position: feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
    }
}
