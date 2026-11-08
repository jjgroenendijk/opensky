// An effect shader's values as cache bytes, in the material block of a model payload.

import OpenSkyFormatsCore
import simd

nonisolated extension ModelCacheCodec {
    static func encode(_ effect: EffectShading, into out: inout CachePayloadWriter) {
        out.value(effect.baseColor)
        out.value(effect.baseColorScale)
        out.string(effect.paletteTexture)
        out.bool(effect.paletteColor)
        out.bool(effect.paletteAlpha)
        out.array(effect.falloff.map { [$0] } ?? [])
        out.bool(effect.vertexColors)
        out.bool(effect.vertexAlpha)
        out.array(effect.softFalloffDepth.map { [$0] } ?? [])
        out.array(effect.lightingInfluence.map { [$0] } ?? [])
        out.bool(effect.externalEmittance)
        out.bool(effect.weaponBlood)
    }

    static func effect(_ input: inout CachePayloadReader) throws -> EffectShading {
        try EffectShading(
            baseColor: input.value(SIMD4<Float>.self),
            baseColorScale: input.value(Float.self),
            paletteTexture: input.string(),
            paletteColor: input.bool(),
            paletteAlpha: input.bool(),
            falloff: input.array(SIMD4<Float>.self).first,
            vertexColors: input.bool(),
            vertexAlpha: input.bool(),
            softFalloffDepth: input.array(Float.self).first,
            lightingInfluence: input.array(Float.self).first,
            externalEmittance: input.bool(),
            weaponBlood: input.bool()
        )
    }
}
