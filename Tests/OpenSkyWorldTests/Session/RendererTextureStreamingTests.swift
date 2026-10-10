// A streamed texture through the real render loop: the frame maps its tiles, copies
// its levels in, and draws the same image as the texture uploaded whole. A missing
// mapping reads zero and draws black. Skips without Metal 4.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

@Suite(.tags(.gpu))
struct RendererTextureStreamingTests {
    private static let device = OffscreenRendererFixture.device
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device
    private static let width = 320
    private static let height = 240
    private static let side = 1024

    private static let camera = SceneCamera(
        eye: SIMD3(0, -400, 150),
        target: SIMD3(0, 0, 32),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    /// A gradient across the texture, the same at every level, so any resident level
    /// draws the same, and two tiles mapped to one heap slot draw wrong.
    private static func ready() -> ReadyTexture {
        let levels = Int(log2(Double(side))) + 1
        var bytes = Data()
        for level in 0 ..< levels {
            let size = max(side >> level, 1)
            for row in 0 ..< size {
                for column in 0 ..< size {
                    bytes.append(contentsOf: [
                        UInt8(column * 256 / size), UInt8(row * 256 / size), 60, 255
                    ])
                }
            }
        }
        return ReadyTexture(
            format: .rgba8, width: side, height: side, mipCount: levels, bytes: bytes
        )
    }

    @MainActor
    private static func render(
        texture: MTLTexture, prepare: (Renderer) -> Void
    ) throws -> [UInt8] {
        let device = try #require(Self.device)
        let model = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 64, halfDepth: 64, height: 64)],
            materials: [Material.fallback], skippedShapeCount: 0
        )
        let render = try RenderModel(device: device, model: model) { _, _ in texture }
        let bounds = try #require(ModelBounds.containing(model: model))
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: width, height: height,
            scene: RenderScene(instances: [
                RenderPlacement(model: render, transform: matrix_identity_float4x4, bounds: bounds)
            ]),
            camera: camera, shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        prepare(renderer)
        return try OffscreenRendererFixture.pixels(
            of: renderer.renderOffscreen(width: width, height: height)
        )
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aStreamedTextureDrawsLikeTheWholeTexture() throws {
        let device = try #require(Self.device)
        let ready = Self.ready()
        let loader = try TextureLoader(device: device)
        let whole = loader.texture(ready: ready, usage: .color, label: "whole")
        var settings = TextureStreamingLoadSettings()
        settings.enabled = true
        let sparse = try #require(loader.sparseTexture(
            ready: ready, usage: .color, label: "streamed", settings: settings
        ))
        let start = sparse.layout.level(fittingWithin: settings.initialSize)
        #expect(start > 0)
        var streamingRenderer: Renderer?
        let streamed = try Self.render(texture: sparse.texture) { renderer in
            streamingRenderer = renderer
            renderer.textureStreaming.enabled = true
            renderer.textureStreaming.mailbox.post(StreamedTextureSeed(
                texture: sparse.texture,
                source: TextureStreamSource(path: "synthetic", usage: .color),
                layout: sparse.layout,
                levels: TextureLevelBytes.levels(of: ready, from: start)
            ))
        }
        let reference = try Self.render(texture: whole) { _ in }
        #expect(OffscreenRendererFixture.litPixelCount(reference) > 100)
        #expect(OffscreenRendererFixture.changedPixels(streamed, reference) == 0)
        let stats = try #require(streamingRenderer).textureStreaming.stats
        #expect(stats.streamedTextures == 1)
        #expect(stats.usedBytes > 0)
    }
}
