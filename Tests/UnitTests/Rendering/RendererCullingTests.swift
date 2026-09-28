// Frustum culling through the real render loop (milestone 3.2): synthetic
// scene, offscreen deterministic frames (RendererOffscreenTests pattern).
// Pixel checks prove visible geometry still draws; SceneDrawStats proves the
// out-of-frustum item was skipped, not rasterized away. Skips without a
// Metal 4 device (paravirtual CI).

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RendererCullingTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    private static let width = 320
    private static let height = 240

    /// Demo-style vantage south-west of the origin, looking at the near
    /// crate.
    private static let facingCamera = SceneCamera(
        eye: SIMD3(-380, -480, 280),
        target: SIMD3(0, 0, 32),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    /// Same world, looking due south away from both crates — everything
    /// lands behind the near plane.
    private static let awayCamera = SceneCamera(
        eye: SIMD3(0, -2000, 100),
        target: SIMD3(0, -4000, 100),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    /// Two instances of one crate model, both with real world AABBs: one at
    /// the origin (in view of `facingCamera`), one 1e6 units east — far
    /// outside the 65 536-unit far plane.
    private static func twoCrateScene(device: MTLDevice) throws -> RenderScene {
        let model = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 32, halfDepth: 32, height: 64)],
            materials: [Material.fallback],
            skippedShapeCount: 0
        )
        let texture = try Self.solidTexture(device: device)
        let render = try RenderModel(device: device, model: model) { _, _ in texture }
        let bounds = try #require(ModelBounds.containing(model: model))
        let nearTransform = matrix_identity_float4x4
        let farTransform = MatrixMath.translation(SIMD3(1_000_000, 0, 0))
        return RenderScene(instances: [
            RenderPlacement(
                model: render,
                transform: nearTransform,
                bounds: bounds.transformed(by: nearTransform)
            ),
            RenderPlacement(
                model: render,
                transform: farTransform,
                bounds: bounds.transformed(by: farTransform)
            )
        ])
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func cullsOutOfFrustumItemAndStillDrawsVisibleOne() throws {
        let device = try #require(Self.device)
        let renderer = try Self.makeRenderer(device: device, camera: Self.facingCamera)
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let pixels = Self.readPixels(texture: texture)

        // Far crate culled, near crate drawn.
        #expect(renderer.lastDrawStats.culledInstances == 1)
        #expect(renderer.lastDrawStats.drawnInstances == 1)
        #expect(renderer.lastDrawStats.drawCalls == 1)
        // Near crate covers the frame center from this vantage.
        let center = ((Self.height / 2) * Self.width + Self.width / 2) * 4
        let centerIsClear = pixels[center] == 0 && pixels[center + 1] == 0
            && pixels[center + 2] == 0
        #expect(!centerIsClear, "frame center is background — visible crate was culled?")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func cameraFacingAwayCullsEverythingAndRendersClear() throws {
        let device = try #require(Self.device)
        let renderer = try Self.makeRenderer(device: device, camera: Self.awayCamera)
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let pixels = Self.readPixels(texture: texture)

        #expect(renderer.lastDrawStats.culledInstances == 2)
        #expect(renderer.lastDrawStats.drawnInstances == 0)
        #expect(renderer.lastDrawStats.drawCalls == 0)
        // All-culled frame is pure clear color (black, alpha 1).
        var lit = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let dark = pixels[pixel] == 0 && pixels[pixel + 1] == 0 && pixels[pixel + 2] == 0
            if !dark {
                lit += 1
            }
        }
        #expect(lit == 0, "all-culled frame should be clear color, \(lit) pixels lit")
    }

    // MARK: - Helpers

    @MainActor
    private static func makeRenderer(
        device: MTLDevice,
        camera: SceneCamera
    ) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(
            view: view,
            scene: twoCrateScene(device: device),
            camera: camera
        )
    }

    private static func solidTexture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba8Unorm_srgb
        descriptor.width = 2
        descriptor.height = 2
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let bytes = [UInt8](repeating: 200, count: 2 * 2 * 4)
        texture.replace(
            region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: 2 * 4
        )
        return texture
    }

    private static func readPixels(texture: MTLTexture) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return } // non-empty
            texture.getBytes(
                base,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return pixels
    }
}
