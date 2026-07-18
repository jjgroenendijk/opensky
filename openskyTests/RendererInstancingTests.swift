// Instanced draws through the real render loop (milestone 3.2): N placements
// of one model must collapse to a single drawIndexedPrimitives with
// instanceCount, land each instance at its own screen position, and compose
// with per-instance frustum culling. Pixel evidence via projected instance
// centers (TerrainSplatRenderTests pattern) + SceneDrawStats assertions.
// Skips without a Metal 4 device (paravirtual CI).

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RendererInstancingTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    private static let width = 480
    private static let height = 320

    /// Head-on from the south so the three crates project to distinct
    /// horizontal screen positions.
    private static let camera = SceneCamera(
        eye: SIMD3(0, -900, 300),
        target: SIMD3(0, 0, 32),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    private static let cratePositions: [SIMD3<Float>] = [
        SIMD3(-260, 0, 0), SIMD3(0, 0, 0), SIMD3(260, 0, 0)
    ]

    /// Three visible crates of one model (+ optionally one far outside the
    /// frustum) — all sharing one RenderMesh, so RenderScene groups them.
    private static func crateScene(
        device: MTLDevice,
        farInstance: Bool
    ) throws -> RenderScene {
        let model = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 32, halfDepth: 32, height: 64)],
            materials: [Material.fallback],
            skippedShapeCount: 0
        )
        let texture = try solidTexture(device: device)
        let render = try RenderModel(device: device, model: model) { _, _ in texture }
        let bounds = try #require(ModelBounds.containing(model: model))
        var positions = cratePositions
        if farInstance {
            positions.append(SIMD3(1_000_000, 0, 0))
        }
        let placements = positions.map { position -> RenderPlacement in
            let transform = MatrixMath.translation(position)
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
    func drawsAllInstancesInOneDrawCall() throws {
        let device = try #require(Self.device)
        let renderer = try Self.makeRenderer(
            device: device,
            scene: Self.crateScene(device: device, farInstance: false)
        )
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let pixels = Self.readPixels(texture: texture)

        // One group, one instanced draw call, three drawn instances.
        #expect(renderer.lastDrawStats.drawCalls == 1)
        #expect(renderer.lastDrawStats.drawnInstances == 3)
        #expect(renderer.lastDrawStats.culledInstances == 0)
        // Pixel evidence: each crate's center projects to a lit pixel in
        // its own screen region, with background between the crates.
        for position in Self.cratePositions {
            let center = position + SIMD3<Float>(0, 0, 32)
            let projected = try #require(Self.project(center))
            #expect(!Self.isBackground(pixels, at: projected), "crate at \(position) missing")
        }
        let gap = try #require(Self.project(SIMD3(-130, 0, 200)))
        #expect(Self.isBackground(pixels, at: gap), "gap between crates should be background")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func cullingComposesWithInstancing() throws {
        let device = try #require(Self.device)
        let renderer = try Self.makeRenderer(
            device: device,
            scene: Self.crateScene(device: device, farInstance: true)
        )
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let pixels = Self.readPixels(texture: texture)

        // Far instance culled per instance; group still draws the other 3.
        #expect(renderer.lastDrawStats.drawCalls == 1)
        #expect(renderer.lastDrawStats.drawnInstances == 3)
        #expect(renderer.lastDrawStats.culledInstances == 1)
        for position in Self.cratePositions {
            let center = position + SIMD3<Float>(0, 0, 32)
            let projected = try #require(Self.project(center))
            #expect(!Self.isBackground(pixels, at: projected), "crate at \(position) missing")
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func makeRenderer(
        device: MTLDevice,
        scene: RenderScene
    ) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view, scene: scene, camera: camera)
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

    /// Projects a world point through the same view + projection the
    /// offscreen render uses; nil when it lands off screen.
    private static func project(_ world: SIMD3<Float>) -> (x: Int, y: Int)? {
        let viewMatrix = FreeFlyCamera(framing: camera).viewMatrix()
        let projection = MatrixMath.perspective(
            fovYRadians: MatrixMath.radians(fromDegrees: 65),
            aspectRatio: Float(width) / Float(height),
            nearZ: Renderer.nearPlane,
            farZ: Renderer.farPlane
        )
        let clip = projection * viewMatrix * SIMD4(world, 1)
        guard clip.w > 0 else { return nil }
        let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
        guard abs(ndc.x) < 1, abs(ndc.y) < 1 else { return nil }
        let x = Int((ndc.x + 1) / 2 * Float(width))
        let y = Int((1 - ndc.y) / 2 * Float(height))
        return (x, y)
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

    private static func isBackground(_ pixels: [UInt8], at point: (x: Int, y: Int)) -> Bool {
        let offset = (point.y * width + point.x) * 4
        return pixels[offset] == 0 && pixels[offset + 1] == 0 && pixels[offset + 2] == 0
    }
}
