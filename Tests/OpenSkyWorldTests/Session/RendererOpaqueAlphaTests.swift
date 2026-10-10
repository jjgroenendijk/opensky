// An opaque draw writes alpha 1, whatever its vertex alpha says. The frame is saved
// and shown as premultiplied color, so a lower alpha turns a lit mesh pure white,
// and zero alpha turns it black. Skips without Metal 4.

import Foundation
import Metal
import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

@Suite(.tags(.gpu))
struct RendererOpaqueAlphaTests {
    private static let device = OffscreenRendererFixture.device
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device
    private static let width = 320
    private static let height = 240

    private static let camera = SceneCamera(
        eye: SIMD3(0, -600, 200),
        target: SIMD3(0, 0, 32),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    /// A terrain blend skirt of a mountain mesh has vertex alpha between 0 and 0.5
    /// and no alpha property, so it draws opaque.
    @Test(.enabled(if: Self.hasMetal4Device), arguments: [Float(0), 0.25])
    @MainActor
    func anOpaqueMeshWithLowVertexAlphaWritesFullAlpha(vertexAlpha: Float) throws {
        let device = try #require(Self.device)
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: Self.width, height: Self.height,
            scene: Self.scene(device: device, vertexAlpha: vertexAlpha),
            camera: Self.camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        let pixels = try OffscreenRendererFixture.pixels(
            of: renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        let center = try #require(OffscreenRendererFixture.project(
            SIMD3(0, 0, 32), camera: Self.camera, width: Self.width, height: Self.height
        ))
        #expect(!OffscreenRendererFixture.isBackground(pixels, at: center, width: Self.width))
        #expect(pixels[(center.y * Self.width + center.x) * 4 + 3] == 255)
    }

    private static func scene(device: MTLDevice, vertexAlpha: Float) throws -> RenderScene {
        let box = DemoScene.boxMesh(halfWidth: 64, halfDepth: 64, height: 64)
        let mesh = Mesh(
            name: box.name, transform: box.transform, positions: box.positions,
            normals: box.normals, tangents: box.tangents, bitangents: box.bitangents,
            uvs: box.uvs,
            colors: Array(repeating: SIMD4(1, 1, 1, vertexAlpha), count: box.positions.count),
            indices: box.indices, materialSlot: box.materialSlot
        )
        let model = Model(meshes: [mesh], materials: [Material.fallback], skippedShapeCount: 0)
        let texture = try OffscreenRendererFixture.solidTexture(device: device)
        let render = try RenderModel(device: device, model: model) { _, _ in texture }
        let bounds = try #require(ModelBounds.containing(model: model))
        return RenderScene(instances: [
            RenderPlacement(model: render, transform: matrix_identity_float4x4, bounds: bounds)
        ])
    }
}
