// The effect shader flags reach the GPU flag bits, and particles keep their colour.

import OpenSkyFormatsCore
@testable import OpenSkyRendering
import OpenSkyShaderTypes
import Testing

struct RenderEffectMaterialTests {
    private static func shading() -> EffectShading {
        EffectShading(
            baseColor: SIMD4(repeating: 1), baseColorScale: 1, paletteTexture: nil,
            paletteColor: false, paletteAlpha: false, falloff: nil, vertexColors: false,
            vertexAlpha: false
        )
    }

    private static func bit(_ flag: EffectFlag) -> UInt32 {
        UInt32(flag.rawValue)
    }

    @Test func softLitAndEmittanceShadingSetTheirBits() {
        var shading = Self.shading()
        shading.softFalloffDepth = 32
        shading.lightingInfluence = 0.75
        shading.externalEmittance = true
        let material = RenderEffectMaterial(shading: shading, palette: nil)
        let wanted = Self.bit(.soft) | Self.bit(.lit) | Self.bit(.externalEmittance)
        #expect(material.flags & wanted == wanted)
        #expect(material.softDepth == 32)
        #expect(material.lightingInfluence == 0.75)
    }

    @Test func aZeroSoftDepthOrNoLightingLeavesTheBitsOff() {
        var shading = Self.shading()
        shading.softFalloffDepth = 0
        let flags = RenderEffectMaterial(shading: shading, palette: nil).flags
        #expect(flags & (Self.bit(.soft) | Self.bit(.lit) | Self.bit(.externalEmittance)) == 0)
    }

    @Test func particlesAlwaysTakeTheirColourAndAlpha() {
        let plain = RenderEffectMaterial(shading: Self.shading(), palette: nil)
        let particles = RenderEffectMaterial.forParticles(plain)
        let colour = Self.bit(.vertexColors) | Self.bit(.vertexAlpha)
        #expect(plain.flags & colour == 0)
        #expect(particles.flags & colour == colour)
    }

    @Test func onlyAdditiveParticleBlendsAddLight() {
        #expect(ParticleBlendMode.additive.addsLight)
        #expect(ParticleBlendMode.additiveOne.addsLight)
        #expect(!ParticleBlendMode.alpha.addsLight)
        #expect(!ParticleBlendMode.multiply.addsLight)
    }

    @Test func aRegionTakesItsColourOnlyOnceTheWeatherGivesOne() {
        let unknown = SIMD4<Float>(1, 1, 1, 0)
        #expect(EmittanceSource.colour(of: nil, regions: [:]) == unknown)
        let red = EmittanceSource.colour(of: .light(SIMD3(1, 0, 0)), regions: [:])
        #expect(red == SIMD4(1, 0, 0, 1))
        #expect(EmittanceSource.colour(of: .region(7), regions: [:]) == unknown)
        let green = EmittanceSource.colour(of: .region(7), regions: [7: SIMD3(0, 1, 0)])
        #expect(green == SIMD4(0, 1, 0, 1))
    }
}
