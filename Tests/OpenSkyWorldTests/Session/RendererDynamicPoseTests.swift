// A simulated body is drawn where the solver put it, proved on pixels. One
// crate belongs to the dynamic world; with its displacement applied it must
// leave its baked spot and appear at the body. `DynamicBodyRenderPoseTests`
// covers the arithmetic. Skips without Metal 4.

import Foundation
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldTesting
import RenderingTesting
import simd
import Testing

struct RendererDynamicPoseTests {
    private static let device = OffscreenRendererFixture.device
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device

    private static let width = 480
    private static let height = 320
    /// The REFR the crate is placed under, and the key its delta is published
    /// beside.
    private static let reference: UInt32 = 0x0000_0200

    private static let camera = SceneCamera(
        eye: SIMD3(0, -900, 300),
        target: SIMD3(0, 0, 32),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    /// Where the cell build baked the crate, and where a shove moves it.
    private static let bakedPosition = SIMD3<Float>(-260, 0, 0)
    private static let shovedPosition = SIMD3<Float>(260, 0, 0)

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aTaggedInstanceIsDrawnAtTheLivePoseRatherThanTheBakedOne() throws {
        let device = try #require(Self.device)
        let renderer = try Self.makeRenderer(device: device)

        // Nothing has moved: the crate is where the build put it.
        let atRest = try OffscreenRendererFixture.pixels(of: renderer.renderOffscreen(
            width: Self.width,
            height: Self.height
        )
        )
        #expect(try !Self.isBackground(atRest, at: #require(Self.project(Self.center(of:
            Self.bakedPosition
        )))))
        #expect(try Self.isBackground(atRest, at: #require(Self.project(Self.center(of:
            Self.shovedPosition
        )))))

        renderer.dynamicInstanceDeltas = [
            Self.reference: MatrixMath.translation(Self.shovedPosition - Self.bakedPosition)
        ]
        let shoved = try OffscreenRendererFixture.pixels(of: renderer.renderOffscreen(
            width: Self.width,
            height: Self.height
        )
        )

        #expect(try Self.isBackground(shoved, at: #require(Self.project(Self.center(of:
            Self.bakedPosition
        )))), "the crate should have left the pose its cell build baked")
        #expect(try !Self.isBackground(shoved, at: #require(Self.project(Self.center(of:
            Self.shovedPosition
        )))), "the crate should be drawn where the body is")
        #expect(renderer.lastDrawStats.drawnInstances == 1)
        #expect(renderer.lastDrawStats.drawCalls == 1)
    }

    /// The culling AABB travels with the instance, so a body that has left the
    /// frustum is culled and one that has entered it is not. Without this the
    /// bounds would keep answering for the pose the build baked.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func theCullingBoundsFollowTheLivePose() throws {
        let device = try #require(Self.device)
        let renderer = try Self.makeRenderer(device: device)
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(renderer.lastDrawStats.culledInstances == 0)

        renderer.dynamicInstanceDeltas = [
            Self.reference: MatrixMath.translation(SIMD3(1_000_000, 0, 0))
        ]
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)

        #expect(renderer.lastDrawStats.culledInstances == 1)
        #expect(renderer.lastDrawStats.drawnInstances == 0)
    }

    // MARK: - Helpers

    /// One crate, tagged as a reference the dynamic world owns.
    @MainActor
    private static func makeRenderer(device: MTLDevice) throws -> Renderer {
        let model = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 32, halfDepth: 32, height: 64)],
            materials: [Material.fallback],
            skippedShapeCount: 0
        )
        let texture = try OffscreenRendererFixture.solidTexture(device: device)
        let render = try RenderModel(device: device, model: model) { _, _ in texture }
        let bounds = try #require(ModelBounds.containing(model: model))
        let transform = MatrixMath.translation(bakedPosition)
        let scene = RenderScene(instances: [RenderPlacement(
            model: render,
            transform: transform,
            bounds: bounds.transformed(by: transform),
            referenceFormID: reference
        )])
        return try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: width, height: height,
            scene: scene,
            camera: camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
    }

    /// The crate's mid-height, which is what projects to a lit pixel.
    private static func center(of position: SIMD3<Float>) -> SIMD3<Float> {
        position + SIMD3(0, 0, 32)
    }

    private static func project(_ world: SIMD3<Float>) -> (x: Int, y: Int)? {
        OffscreenRendererFixture.project(world, camera: camera, width: width, height: height)
    }

    private static func isBackground(_ pixels: [UInt8], at point: (x: Int, y: Int)) -> Bool {
        OffscreenRendererFixture.isBackground(pixels, at: point, width: width)
    }
}
