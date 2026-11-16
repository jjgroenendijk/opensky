// A directional material's draw values: the tile each kind repeats at and the shader mode.

import OpenSkyFormatsCore
@testable import OpenSkyRenderResources
import Testing

struct RenderProjectedMaterialTests {
    private static func material(singlePass: Bool, isSnow: Bool) -> ProjectedMaterial {
        ProjectedMaterial(
            diffuseTexture: nil, noiseTexture: nil, direction: SIMD3(0, 0, 2), maxAngle: 60,
            falloffScale: 0.35, falloffBias: 0.4, noiseUVScale: 48, materialUVScale: 256,
            singlePassColor: SIMD3(0.4, 0.45, 0.5), singlePass: singlePass, isSnow: isSnow,
            normalDampener: 0.75
        )
    }

    private static func mode(
        _ projected: RenderProjectedMaterial?,
        mesh: (Bool, Bool) = (false, false),
        improvedSnow: Bool = true
    ) -> Float {
        RenderProjectedMaterial.mode(
            projected, mesh: mesh, texturesEnabled: true, improvedSnow: improvedSnow
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
        #expect(render.color == SIMD4(0.75, 0, 0, 48))
    }

    @Test
    func modeFallsBackToTheColourAndMarksSnow() {
        let render = RenderProjectedMaterial(
            Self.material(singlePass: true, isSnow: true), diffuse: nil, noise: nil
        )
        #expect(Self.mode(render) == 5)
        #expect(Self.mode(render, improvedSnow: false) == 1)
        #expect(Self.mode(render, mesh: (true, true)) == 29)
    }

    @Test
    func anOverlayWithoutItsTextureDrawsNothing() {
        let render = RenderProjectedMaterial(
            Self.material(singlePass: false, isSnow: true), diffuse: nil, noise: nil
        )
        #expect(Self.mode(render) == 0)
    }

    @Test
    func aSnowMeshNeedsNoDirectionalMaterial() {
        #expect(Self.mode(nil, mesh: (true, false)) == 8)
        #expect(Self.mode(nil, mesh: (true, false), improvedSnow: false) == 0)
        #expect(Self.mode(nil) == 0)
    }
}
