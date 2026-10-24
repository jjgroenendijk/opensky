// Texture streaming measures every map a material samples by UV, not only the diffuse,
// each at the UV density the shader reads it with.

import Metal
import OpenSkyFormatsCore
@testable import OpenSkyRenderResources
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct RenderMaterialStreamedMapsTests {
    nonisolated private static let device = MTLCreateSystemDefaultDevice()

    nonisolated private static var hasDevice: Bool {
        device != nil
    }

    private static let keys = ["d", "n", "t", "g", "detail", "cube", "m", "b", "noise", "inner"]

    /// Each key gets its own texture, labelled with the key, so a test can tell maps apart.
    private static func material(_ material: Material) throws -> RenderMaterial {
        let device = try #require(Self.device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false
        )
        var textures: [String: MTLTexture] = [:]
        for key in keys + ["none"] {
            let texture = try #require(device.makeTexture(descriptor: descriptor))
            texture.label = key
            textures[key] = texture
        }
        let placeholder = try #require(textures["none"])
        let lookup = textures
        return RenderMaterial(material: material) { key, _ in
            key.flatMap { lookup[$0] } ?? placeholder
        }
    }

    private static func base(shading: SurfaceShading) -> Material {
        Material(
            diffuseTexture: "d", normalTexture: "n", uvOffset: .zero, uvScale: SIMD2(1, 1),
            alpha: 1, glossiness: 80, specularColor: SIMD3(1, 1, 1), specularStrength: 1,
            doubleSided: false, alphaBlend: false, alphaTestThreshold: nil,
            tintTexture: "t", shading: shading
        )
    }

    private static func densities(_ material: RenderMaterial) -> [String: Float] {
        let maps = material.streamedMaps(uvPerUnit: 0.01)
        return Dictionary(maps.map { ($0.texture.label ?? "", $0.uvPerUnit) }) { first, _ in first }
    }

    @Test(.enabled(if: Self.hasDevice)) func everyUVMapSharesTheDiffuseDensity() throws {
        var shading = SurfaceShading()
        shading.glowTexture = "g"
        shading.detailTexture = "detail"
        shading.environmentTexture = "cube"
        shading.environmentMaskTexture = "m"
        shading.backLightTexture = "b"
        let maps = try Self.densities(Self.material(Self.base(shading: shading)))
        for key in ["d", "n", "t", "g", "detail", "m", "b"] {
            #expect(maps[key] == 0.01, "\(key)")
        }
        // A cube map is sampled by direction, so the rule does not measure it.
        #expect(maps["cube"] == nil)
    }

    @Test(.enabled(if: Self.hasDevice)) func landscapeNoiseRepeatsInWorldSpace() throws {
        var shading = SurfaceShading()
        shading.terms = [.landscapeNoise]
        shading.detailTexture = "noise"
        let maps = try Self.densities(Self.material(Self.base(shading: shading)))
        #expect(maps["noise"] == RenderMaterial.landscapeNoiseUVPerUnit)
    }

    @Test(.enabled(if: Self.hasDevice)) func innerLayerUsesItsFinerScale() throws {
        var shading = SurfaceShading()
        shading.terms = [.multiLayer]
        shading.innerLayerTexture = "inner"
        shading.multiLayer.innerScale = SIMD2(4, 2)
        let maps = try Self.densities(Self.material(Self.base(shading: shading)))
        #expect(maps["inner"] == 0.04)
    }
}
