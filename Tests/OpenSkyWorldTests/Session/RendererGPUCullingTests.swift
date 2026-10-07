// GPU culling through the real render loop: the compute pass must keep the same
// instances the CPU frustum test keeps, for the camera and every shadow cascade, and
// the frame must look the same. Skips without Metal 4.

import EngineTesting
import Foundation
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct RendererGPUCullingTests {
    private static let device = OffscreenRendererFixture.device
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device

    private static let width = 320
    private static let height = 240

    /// Looks east along the crate row from its west end, so the far half and the
    /// crates behind the eye fall outside the camera frustum.
    private static let camera = SceneCamera(
        eye: SIMD3(-2600, -900, 300),
        target: SIMD3(-600, 0, 32),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    /// A row of crates from x = -6000 to 6000, plus one taller crate a physics body
    /// moves, which must stay on the CPU path.
    private static func crateRowScene(device: MTLDevice) throws -> RenderScene {
        let texture = try OffscreenRendererFixture.solidTexture(device: device)
        func placements(height: Float, xs: [Float], reference: UInt32) throws -> [RenderPlacement] {
            let model = Model(
                meshes: [DemoScene.boxMesh(halfWidth: 32, halfDepth: 32, height: height)],
                materials: [Material.fallback],
                skippedShapeCount: 0
            )
            let render = try RenderModel(device: device, model: model) { _, _ in texture }
            let bounds = try #require(ModelBounds.containing(model: model))
            return xs.map { x in
                let transform = MatrixMath.translation(SIMD3(x, 0, 0))
                return RenderPlacement(
                    model: render,
                    transform: transform,
                    bounds: bounds.transformed(by: transform),
                    referenceFormID: reference
                )
            }
        }
        let row = stride(from: Float(-6000), through: 6000, by: 400).map(\.self)
        return try RenderScene(
            instances: placements(height: 64, xs: row, reference: 0)
                + placements(height: 128, xs: [-1000], reference: 0x0001_0F00)
        )
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func gpuPathKeepsTheSameInstancesAsTheCPUPath() throws {
        let device = try #require(Self.device)
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: Self.width, height: Self.height,
            scene: Self.crateRowScene(device: device),
            camera: Self.camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        renderer.gpuCullingEnabled = false
        let cpuPixels = try OffscreenRendererFixture.pixels(
            of: renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        let cpu = renderer.lastDrawStats
        let cpuShadow = renderer.lastShadowDrawStats
        #expect(cpu.drawnInstances > 1)
        #expect(cpu.culledInstances > 1)
        #expect(cpuShadow.drawnInstances > 0)

        renderer.gpuCullingEnabled = true
        let gpuPixels = try OffscreenRendererFixture.pixels(
            of: renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        let gpu = renderer.lastFrameGPUCullCounts()
        // The moving crate is the only instance the CPU still tests.
        let moving = renderer.lastDrawStats
        #expect(moving.drawnInstances + moving.culledInstances == 1)
        #expect(gpu.cameraVisible + moving.drawnInstances == cpu.drawnInstances)
        #expect(gpu.cameraCulled + moving.culledInstances == cpu.culledInstances)
        let movingShadow = renderer.lastShadowDrawStats
        #expect(gpu.shadowVisible + movingShadow.drawnInstances == cpuShadow.drawnInstances)
        #expect(gpu.shadowCulled + movingShadow.culledInstances == cpuShadow.culledInstances)
        #expect(renderer.lastGPUCullCounts == CullCounts(), "counts are read a few frames late")
        let differing = zip(cpuPixels, gpuPixels).count { $0 != $1 }
        #expect(differing == 0, "\(differing) bytes differ between the CPU and GPU frames")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func turningCullingOffClearsTheGPUCounts() throws {
        let device = try #require(Self.device)
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: Self.width, height: Self.height,
            scene: Self.crateRowScene(device: device),
            camera: Self.camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        renderer.gpuCullingEnabled = true
        for _ in 0 ..< 4 {
            _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        }
        #expect(renderer.lastGPUCullCounts.cameraVisible > 0)
        renderer.gpuCullingEnabled = false
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(renderer.lastGPUCullCounts == CullCounts())
    }
}
