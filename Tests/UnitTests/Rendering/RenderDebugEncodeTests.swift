// Render debug views + layer isolation reaching the GPU (issue #144).
//
// The state-level rules are pinned in `RenderDebugStateTests`; this suite is the
// evidence that they change what the passes encode: draw-stat deltas for the
// scene and shadow passes, and pixel proof that a debug channel changes the
// frame while an ordinary offscreen render still renders the shipping one.
// Skips without a Metal 4 device (paravirtual CI).

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RenderDebugEncodeTests {
    // MARK: - Encode-level isolation (device gated)

    /// The solo toggle is renderer state rather than encode state, but it needs
    /// a live `Renderer` to exercise, so it is gated with the rest.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func soloingTheAlreadySoloedLayerRestoresEveryLayer() throws {
        let renderer = try #require(Self.headlessRenderer())
        renderer.soloRenderLayer(.grass)
        #expect(renderer.renderDebug.layers == .grass)
        #expect(renderer.renderDebug.soloedLayer == .grass)
        renderer.soloRenderLayer(.grass)
        #expect(renderer.renderDebug.layers == .all)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func isolatingALayerRemovesItsSceneAndShadowDraws() throws {
        let renderer = try #require(Self.twoLayerRenderer())
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let baseline = renderer.lastDrawStats
        let baselineShadow = renderer.lastShadowDrawStats
        #expect(baseline.drawCalls == 2)
        #expect(baseline.drawnInstances == 2)
        #expect(baselineShadow.drawnInstances > 0)

        // The mask is a dev-shell view filter, so an ordinary offscreen frame
        // ignores it exactly as it ignores the debug channel.
        renderer.renderDebug.layers = .statics
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(renderer.lastDrawStats.drawCalls == baseline.drawCalls)

        renderer.renderDebugAppliesOffscreen = true
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(renderer.lastDrawStats.drawCalls == 1)
        #expect(renderer.lastDrawStats.drawnInstances == 1)
        // The shadow pass honours the same mask: a hidden caster leaves no
        // shadow behind, which is what makes the tool trustworthy.
        #expect(renderer.lastShadowDrawStats.drawnInstances < baselineShadow.drawnInstances)
        #expect(renderer.lastShadowDrawStats.drawnInstances > 0)

        renderer.renderDebug.layers = []
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(renderer.lastDrawStats.drawCalls == 0)
        #expect(renderer.lastShadowDrawStats.drawnInstances == 0)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aDebugChannelChangesTheFrameOnlyWhenOffscreenOptsIn() throws {
        let renderer = try #require(Self.twoLayerRenderer())
        let shipping = try Self.readPixels(
            texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
        )

        // Default: the dev-shell filter never leaks into an offscreen frame.
        renderer.renderDebug.mode = .layerCategory
        let suppressed = try Self.readPixels(
            texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        #expect(suppressed == shipping)

        renderer.renderDebugAppliesOffscreen = true
        let debugged = try Self.readPixels(
            texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        #expect(debugged != shipping)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func wireframeRasterisesFewerLitPixelsThanTheSolidFrame() throws {
        let renderer = try #require(Self.twoLayerRenderer())
        renderer.renderDebugAppliesOffscreen = true
        let solid = try Self.litPixelCount(
            renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        renderer.renderDebug.mode = .wireframe
        let wire = try Self.litPixelCount(
            renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        #expect(wire > 0, "wireframe drew nothing")
        #expect(wire < solid, "wireframe should cover fewer pixels than the filled frame")
    }

    // MARK: - Helpers

    private static let width = 320
    private static let height = 240

    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    private static let camera = SceneCamera(
        eye: SIMD3(-380, -480, 280),
        target: SIMD3(0, 0, 32),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    /// A renderer over the demo scene, for the pure-state assertions that still
    /// need a live `Renderer`. nil without a Metal 4 device.
    @MainActor
    private static func headlessRenderer() -> Renderer? {
        guard let device else { return nil }
        return try? Renderer(view: makeView(device: device))
    }

    /// One crate drawn as a static and a second, offset crate drawn as an
    /// actor: two groups that differ only in scene role, which is exactly what
    /// the layer filter has to be able to tell apart.
    @MainActor
    private static func twoLayerRenderer() -> Renderer? {
        guard let device else { return nil }
        return try? Renderer(
            view: makeView(device: device),
            scene: twoLayerScene(device: device),
            camera: camera
        )
    }

    @MainActor
    private static func makeView(device: MTLDevice) -> MTKView {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return view
    }

    private static func twoLayerScene(device: MTLDevice) throws -> RenderScene {
        let model = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 32, halfDepth: 32, height: 64)],
            materials: [Material.fallback],
            skippedShapeCount: 0
        )
        let texture = try solidTexture(device: device)
        let render = try RenderModel(device: device, model: model) { _, _ in texture }
        let bounds = try #require(ModelBounds.containing(model: model))
        let actorTransform = MatrixMath.translation(SIMD3(96, 0, 0))
        return RenderScene(instances: [
            RenderPlacement(
                model: render,
                transform: matrix_identity_float4x4,
                bounds: bounds.transformed(by: matrix_identity_float4x4),
                layer: .statics
            ),
            RenderPlacement(
                model: render,
                transform: actorTransform,
                bounds: bounds.transformed(by: actorTransform),
                layer: .actors
            )
        ])
    }

    private static func solidTexture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        var pixel: [UInt8] = [220, 220, 220, 255]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &pixel,
            bytesPerRow: 4
        )
        return texture
    }

    private static func readPixels(texture: MTLTexture) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return pixels
    }

    private static func litPixelCount(_ texture: MTLTexture) -> Int {
        let pixels = readPixels(texture: texture)
        var lit = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4)
            where pixels[pixel] != 0 || pixels[pixel + 1] != 0 || pixels[pixel + 2] != 0
        {
            lit += 1
        }
        return lit
    }
}
