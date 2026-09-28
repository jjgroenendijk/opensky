// A simulated body is drawn where the solver put it (issue #193), proved on
// pixels rather than on matrices: one crate is tagged as a reference the
// dynamic world owns, the renderer is handed the displacement that world would
// publish, and the crate has to be gone from where the cell build baked it and
// present where the body is. The arithmetic behind the displacement is
// DynamicBodyRenderPoseTests; this is the evidence it reaches the screen.
//
// Skips without a Metal 4 device (paravirtual CI), like every render suite.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RendererDynamicPoseTests {
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
        let atRest = try Self.readPixels(
            texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
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
        let shoved = try Self.readPixels(
            texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
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
        let texture = try solidTexture(device: device)
        let render = try RenderModel(device: device, model: model) { _, _ in texture }
        let bounds = try #require(ModelBounds.containing(model: model))
        let transform = MatrixMath.translation(bakedPosition)
        let scene = RenderScene(instances: [RenderPlacement(
            model: render,
            transform: transform,
            bounds: bounds.transformed(by: transform),
            referenceFormID: reference
        )])
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view, scene: scene, camera: camera)
    }

    /// The crate's mid-height, which is what projects to a lit pixel.
    private static func center(of position: SIMD3<Float>) -> SIMD3<Float> {
        position + SIMD3(0, 0, 32)
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
        return (
            x: Int((ndc.x + 1) / 2 * Float(width)),
            y: Int((1 - ndc.y) / 2 * Float(height))
        )
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
