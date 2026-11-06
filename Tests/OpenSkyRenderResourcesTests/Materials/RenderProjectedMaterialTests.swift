// A directional material's draw values: the tile each kind repeats at and the shader mode.

import OpenSkyFormatsCore
@testable import OpenSkyRenderResources
import Testing

struct RenderProjectedMaterialTests {
    private static func material(singlePass: Bool, isSnow: Bool) -> ProjectedMaterial {
        ProjectedMaterial(
            diffuseTexture: nil, noiseTexture: nil, direction: SIMD3(0, 0, 2), maxAngle: 60,
            falloffScale: 0.35, falloffBias: 0.4, noiseUVScale: 48, materialUVScale: 256,
            singlePassColor: SIMD3(0.4, 0.45, 0.5), singlePass: singlePass, isSnow: isSnow
        )
    }

    @Test
    func singlePassRepeatsEveryTwoNoiseTiles() {
        let render = RenderProjectedMaterial(
            Self.material(singlePass: true, isSnow: false), diffuse: nil, noise: nil
        )
        #expect(render.parameters == SIMD4(0.35, 0.4, 96, 0))
        #expect(render.color.w == 48)
        #expect(abs(render.direction.w - 0.5) < 1e-5)
        #expect(render.direction.z == 1)
    }

    @Test
    func overlayRepeatsEveryMaterialTile() {
        let render = RenderProjectedMaterial(
            Self.material(singlePass: false, isSnow: false), diffuse: nil, noise: nil
        )
        #expect(render.parameters.z == 256)
    }

    @Test
    func modeFallsBackToTheColourAndMarksSnow() {
        let render = RenderProjectedMaterial(
            Self.material(singlePass: true, isSnow: true), diffuse: nil, noise: nil
        )
        #expect(render.mode(texturesEnabled: true, improvedSnow: true) == 5)
        #expect(render.mode(texturesEnabled: true, improvedSnow: false) == 1)
    }
}
