// Renderer.setScene through real offscreen frames (milestone 3.2 streaming
// precondition): swap to a larger scene forces the draw-uniform ring to
// regrow while frames from the old scene may still be in flight; swap to an
// empty scene must render pure clear. Pixel checks + capacity assertions,
// RendererOffscreenTests pattern. Skips without a Metal 4 device.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RendererSceneSwapTests {
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
        let texture = try solidTexture(device: device)
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
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: Self.crateScene(device: device, count: 1),
            camera: Self.camera
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
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: Self.crateScene(device: device, count: 3),
            camera: Self.camera
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
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: RenderScene(instances: []),
            camera: Self.camera
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

    // MARK: - Helpers

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

    private static func litPixelCount(texture: MTLTexture) -> Int {
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
        var lit = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let dark = pixels[pixel] == 0 && pixels[pixel + 1] == 0 && pixels[pixel + 2] == 0
            if !dark {
                lit += 1
            }
        }
        return lit
    }
}
