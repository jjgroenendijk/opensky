// `Renderer.setScene` through real offscreen frames. A larger scene regrows
// the draw-uniform ring while old frames may still be in flight, and an empty
// scene renders pure clear. Skips without Metal 4.

import Foundation
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldTesting
import RenderingTesting
import simd
import Testing

struct RendererSceneSwapTests {
    private static let device = OffscreenRendererFixture.device
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device

    private static let width = 320
    private static let height = 240

    private static let camera = SceneCamera(
        eye: SIMD3(-380, -480, 280),
        target: SIMD3(0, 0, 32),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    /// `count` crates in a row around the origin, real bounds. Each crate
    /// gets its OWN RenderModel (no instancing collapse) so both the
    /// per-group uniform ring and the per-instance transform ring must
    /// regrow when count exceeds their capacities.
    private static func crateScene(device: MTLDevice, count: Int) throws -> RenderScene {
        let texture = try OffscreenRendererFixture.solidTexture(device: device)
        let placements = try (0 ..< count).map { index -> RenderPlacement in
            let model = Model(
                meshes: [DemoScene.boxMesh(halfWidth: 32, halfDepth: 32, height: 64)],
                materials: [Material.fallback],
                skippedShapeCount: 0
            )
            let render = try RenderModel(device: device, model: model) { _, _ in texture }
            let bounds = try #require(ModelBounds.containing(model: model))
            let transform = MatrixMath.translation(
                SIMD3(Float(index - count / 2) * 80, 0, 0)
            )
            return RenderPlacement(
                model: render,
                transform: transform,
                bounds: bounds.transformed(by: transform)
            )
        }
        return RenderScene(instances: placements)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func swapToLargerSceneRegrowsRingAndRenders() throws {
        let device = try #require(Self.device)
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: Self.width, height: Self.height,
            scene: Self.crateScene(device: device, count: 1),
            camera: Self.camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        #expect(renderer.drawUniformSlotCapacity == 1)
        #expect(renderer.instanceSlotCapacity == 1)

        let first = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(Self.litPixelCount(texture: first) > 0)

        // Larger scene B: 9 groups / 9 instances > capacity 1 -> both rings
        // regrow (pow2 -> 16), old rings + old scene retired while frame 1
        // may be in flight.
        try renderer.setScene(Self.crateScene(device: device, count: 9))
        #expect(renderer.drawUniformSlotCapacity == 16)
        #expect(renderer.instanceSlotCapacity == 16)
        let second = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let firstLit = Self.litPixelCount(texture: first)
        let secondLit = Self.litPixelCount(texture: second)
        #expect(secondLit > firstLit, "9 crates should light more pixels than 1")
        #expect(renderer.lastDrawStats.drawnInstances > 1)

        // Swap A -> B -> back to a fresh small scene: retire list handles
        // consecutive swaps; render still sane.
        try renderer.setScene(Self.crateScene(device: device, count: 1))
        let third = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(Self.litPixelCount(texture: third) > 0)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func swapToEmptySceneRendersClear() throws {
        let device = try #require(Self.device)
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: Self.width, height: Self.height,
            scene: Self.crateScene(device: device, count: 3),
            camera: Self.camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)

        try renderer.setScene(RenderScene(instances: []))
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(Self.litPixelCount(texture: texture) == 0)
        #expect(renderer.lastDrawStats == SceneDrawStats())
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func swapCameraReseedsFreeFlyPose() throws {
        let device = try #require(Self.device)
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: Self.width, height: Self.height,
            scene: RenderScene(instances: []),
            camera: Self.camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )

        // Camera facing away from the crates: nothing on screen even after
        // the scene swap without a reseed...
        let behind = SceneCamera(
            eye: SIMD3(0, -2000, 100),
            target: SIMD3(0, -4000, 100),
            sunDirection: DemoScene.sunDirection,
            sunColor: DemoScene.sunColor,
            ambientColor: DemoScene.ambientColor
        )
        try renderer.setScene(Self.crateScene(device: device, count: 3), camera: behind)
        let away = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(Self.litPixelCount(texture: away) == 0)

        // ...and the crates appear once the swap hands in a framing camera.
        try renderer.setScene(Self.crateScene(device: device, count: 3), camera: Self.camera)
        let framed = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(Self.litPixelCount(texture: framed) > 0)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func sceneCameraReseedResetsWalkPoseBeforeNextPhysicsStep() throws {
        let device = try #require(Self.device)
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: Self.width, height: Self.height,
            scene: RenderScene(instances: []),
            camera: Self.camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        let groundHeight = renderer.walkController.feetPosition.z
        renderer.walkController.update(
            camera: &renderer.freeFlyCamera,
            input: CameraInput(dt: WalkController.fixedTimeStep),
            sampleGround: { _ in
                TerrainGroundSample(height: groundHeight, normal: SIMD3(0, 0, 1))
            }
        )
        #expect(renderer.walkController.isGrounded)

        let destination = SceneCamera(
            eye: SIMD3(100, 200, 300),
            target: SIMD3(101, 200, 300),
            sunDirection: DemoScene.sunDirection,
            sunColor: DemoScene.sunColor,
            ambientColor: DemoScene.ambientColor
        )
        try renderer.setScene(RenderScene(instances: []), camera: destination)

        #expect(renderer.walkController.cameraPosition == destination.eye)
        #expect(renderer.walkController.verticalVelocity == 0)
        #expect(!renderer.walkController.isGrounded)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func teleportCameraUsesActorOriginAsWalkFeet() throws {
        let device = try #require(Self.device)
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: Self.width, height: Self.height,
            scene: RenderScene(instances: []),
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        renderer.movementMode = .walk
        let placement = PlacedReference.Placement(
            position: SIMD3(10, 20, 30),
            rotation: SIMD3(0, 0, 0.5)
        )
        try renderer.setScene(
            RenderScene(instances: []),
            camera: SceneCamera.teleport(placement: placement)
        )

        #expect(renderer.walkController.feetPosition == placement.position)
        #expect(renderer.freeFlyCamera.position.z == 30 + PlayerCapsule.standard.eyeHeight)
        #expect(abs(renderer.freeFlyCamera.yaw - 0.5) < 0.001)
    }

    // MARK: - Helpers

    private static func litPixelCount(texture: MTLTexture) -> Int {
        OffscreenRendererFixture.litPixelCount(OffscreenRendererFixture.pixels(of: texture))
    }
}
