// Blended rigid shapes leave the opaque list, cast no sun shadow, and draw
// farthest first.

import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct BlendedDrawGroupTests {
    private static let device = MTLCreateSystemDefaultDevice()

    private static var hasDevice: Bool {
        device != nil
    }

    private static func material(blended: Bool, threshold: Float? = nil) -> Material {
        Material(
            diffuseTexture: "texture", normalTexture: nil, uvOffset: .zero, uvScale: SIMD2(1, 1),
            alpha: 1, glossiness: 80, specularColor: SIMD3(1, 1, 1), specularStrength: 0,
            doubleSided: false, alphaBlend: blended, alphaTestThreshold: threshold
        )
    }

    /// One model per placement, so no two placements share a group.
    private static func placement(
        _ material: Material, at position: SIMD3<Float>, device: MTLDevice
    ) throws -> RenderPlacement {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let model = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 8, halfDepth: 8, height: 8)],
            materials: [material],
            skippedShapeCount: 0
        )
        return try RenderPlacement(
            model: RenderModel(device: device, model: model) { _, _ in texture },
            transform: MatrixMath.translation(position)
        )
    }

    @Test(.enabled(if: Self.hasDevice))
    func blendedShapeRidesTheAlphaTestedListAndCastsNoShadow() throws {
        let device = try #require(Self.device)
        let scene = try RenderScene(instances: [
            Self.placement(Self.material(blended: false), at: .zero, device: device),
            Self.placement(Self.material(blended: true), at: .zero, device: device)
        ])
        #expect(scene.opaque.count == 1)
        let opaqueCastShadows = scene.opaque.allSatisfy(\.castsShadows)
        #expect(opaqueCastShadows)
        let blended = try #require(scene.alphaTested.first)
        #expect(scene.alphaTested.count == 1)
        #expect(blended.drawsBlended)
        #expect(!blended.castsShadows)
    }

    @Test(.enabled(if: Self.hasDevice))
    func blendedGroupsDrawFarthestFirst() throws {
        let device = try #require(Self.device)
        let scene = try RenderScene(instances: [
            Self.placement(Self.material(blended: true), at: SIMD3(100, 0, 0), device: device),
            Self.placement(
                Self.material(blended: false, threshold: 0.5),
                at: .zero,
                device: device
            ),
            Self.placement(Self.material(blended: true), at: SIMD3(900, 0, 0), device: device),
            Self.placement(Self.material(blended: true), at: SIMD3(400, 0, 0), device: device)
        ])
        let order = Renderer.blendedDrawOrder(scene.alphaTested, eye: .zero)
        #expect(order.map { scene.alphaTested[$0].lightingCenter.x } == [900, 400, 100])
    }
}
