// The ground contact reports the material under the player's feet. Each
// collision shape carries a material, and the footstep chain reads it.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
@testable import OpenSkyPlayer
@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
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

    @Test func aPlacementStandsOnTheFloorFromAnyHeight() {
        let query = DynamicBodyScene.candidateQuery([DynamicBodyScene.floor(z: 10)])
        var low = WalkController(cameraPosition: SIMD3(0, 0, 30))
        let placed1 = low.standOnGround(sampleGround: { _ in nil }, query: query)
        #expect(placed1)
        #expect(low.feetPosition.z == 10)
        var high = WalkController(cameraPosition: SIMD3(0, 0, 4000))
        let placed2 = high.standOnGround(sampleGround: { _ in nil }, query: query)
        #expect(placed2)
        #expect(high.feetPosition.z == 10)
    }

    @Test func aPlacementPrefersAFloorAboveTheTerrainButBelowTheEye() {
        let terrain: WalkController.GroundSampler = { _ in
            TerrainGroundSample(height: -500, normal: SIMD3(0, 0, 1))
        }
        let query = DynamicBodyScene.candidateQuery([DynamicBodyScene.floor(z: 10)])
        var onBridge = WalkController(cameraPosition: SIMD3(0, 0, 3000))
        onBridge.standOnGround(sampleGround: terrain, query: query)
        #expect(onBridge.feetPosition.z == 10)
        var underBridge = WalkController(cameraPosition: SIMD3(0, 0, -400))
        underBridge.standOnGround(sampleGround: terrain, query: query)
        #expect(underBridge.feetPosition.z == -500)
        var underground = WalkController(cameraPosition: SIMD3(0, 0, -900))
        underground.standOnGround(sampleGround: terrain, query: { _ in [] })
        #expect(underground.feetPosition.z == -500)
        var nothingLoaded = WalkController(cameraPosition: SIMD3(0, 0, 700))
        let placed3 = nothingLoaded.standOnGround(sampleGround: { _ in nil }, query: { _ in [] })
        #expect(!placed3)
        #expect(nothingLoaded.feetPosition.z == 700 - nothingLoaded.capsule.eyeHeight)
    }

    @Test func aPlacementUnderTheWorldStandsOnTheSurfaceAbove() {
        let deepTerrain: WalkController.GroundSampler = { _ in
            TerrainGroundSample(height: -60000, normal: SIMD3(0, 0, 1))
        }
        let streets = DynamicBodyScene.candidateQuery([DynamicBodyScene.floor(z: -2000)])
        var belowStreets = WalkController(cameraPosition: SIMD3(0, 0, -2800))
        belowStreets.standOnGround(sampleGround: deepTerrain, query: streets)
        #expect(belowStreets.feetPosition.z == -2000)
        var high = WalkController(cameraPosition: SIMD3(0, 0, 50000))
        high.standOnGround(sampleGround: deepTerrain, query: { _ in [] })
        #expect(high.feetPosition.z == -60000)
    }

    @Test func aPlacementInDeepWaterFloatsAtTheSurface() {
        let lakeBed: WalkController.GroundSampler = { _ in
            TerrainGroundSample(height: -2000, normal: SIMD3(0, 0, 1))
        }
        let lake: (SIMD3<Float>) -> WaterReading? = { _ in WaterReading(surface: 0) }
        var swimmer = WalkController(cameraPosition: SIMD3(0, 0, 100))
        swimmer.standOnGround(sampleGround: lakeBed, query: { _ in [] }, water: lake)
        // A 128-unit body at float level 1.6 rests with its feet 112.4 units under.
        #expect(abs(swimmer.feetPosition.z + 112.4) < 1e-3)
        let shallow: (SIMD3<Float>) -> WaterReading? = { _ in WaterReading(surface: -1950) }
        var wader = WalkController(cameraPosition: SIMD3(0, 0, 100))
        wader.standOnGround(sampleGround: lakeBed, query: { _ in [] }, water: shallow)
        #expect(wader.feetPosition.z == -2000)
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
