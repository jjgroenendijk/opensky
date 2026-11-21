// A translucent surface mixes with the colour behind it in gamma space, as the game
// stores colour: over black, a quarter-alpha box shows a quarter of its opaque value.

import Metal
import MetalKit
import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
@testable import OpenSkyRenderResources
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
@MainActor
struct GammaBlendTests {
    private static let size = 64
    private static let alpha: Float = 0.25

    private static func material(blended: Bool) -> Material {
        Material(
            diffuseTexture: "texture", normalTexture: nil, uvOffset: .zero, uvScale: SIMD2(1, 1),
            alpha: blended ? alpha : 1, glossiness: 0, specularColor: .zero, specularStrength: 0,
            doubleSided: false, alphaBlend: blended, alphaTestThreshold: nil
        )
    }

    private static func opaqueGrey(device: any MTLDevice) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: 1, height: 1, mipmapped: false
        )
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let bytes: [UInt8] = [200, 200, 200, 255]
        unsafe texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 4
        )
        return texture
    }

    private static func centre(blended: Bool) throws -> Int {
        let device = try #require(OffscreenRendererFixture.device)
        let texture = try opaqueGrey(device: device)
        let model = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 200, halfDepth: 200, height: 200)],
            materials: [material(blended: blended)],
            skippedShapeCount: 0
        )
        let placement = try RenderPlacement(
            model: RenderModel(device: device, model: model) { _, _ in texture },
            transform: matrix_identity_float4x4
        )
        let camera = SceneCamera(
            eye: SIMD3(0, -700, 100), target: SIMD3(0, 0, 100),
            sunDirection: SceneCamera.demo.sunDirection, sunColor: SceneCamera.demo.sunColor,
            ambientColor: SIMD3(repeating: 1)
        )
        let renderer = try OffscreenRendererFixture.makeRenderer(
            device: device, width: size, height: size,
            scene: RenderScene(instances: [placement]), camera: camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        renderer.shadowQuality = .off
        renderer.frameInput.isPaused = true
        let pixels = try OffscreenRendererFixture.render(renderer, width: size, height: size)
        let offset = (size / 2 * size + size / 2) * 4
        return Int(pixels[offset + 1])
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func aTranslucentBoxOverBlackShowsItsAlphaTimesTheOpaqueValue() throws {
        let opaque = try Self.centre(blended: false)
        let blended = try Self.centre(blended: true)
        #expect(opaque > 40, "the opaque box is too dark to compare: \(opaque)")
        let expected = Int((Float(opaque) * Self.alpha).rounded())
        #expect(abs(blended - expected) <= 6, "blended \(blended), expected about \(expected)")
    }
}
