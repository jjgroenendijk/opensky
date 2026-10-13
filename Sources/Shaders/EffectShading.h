#pragma once

// BSEffectShaderProperty shading: unlit, base color, palette, and falloff. The
// model follows NifSkope's open-source effect shader (sk_effectshader.frag).

#include "ShaderCommon.h"

struct EffectTerms
{
    uint flags;
    /// Start and stop angle cosines, then start and stop opacity.
    float4 falloff;
    float4 baseColor;
    float baseColorScale;
};

static inline float4 effectShade(
    float4 base,
    float4 vertexColor,
    float3 normal,
    float3 toEye,
    EffectTerms terms,
    texture2d<float> palette)
{
    constexpr sampler paletteSampler(filter::linear, address::clamp_to_edge);
    uint flags = terms.flags;
    float4 tint = (flags & EffectFlagVertexColors) != 0 ? vertexColor : float4(1.0);
    tint.a = (flags & EffectFlagVertexAlpha) != 0 ? vertexColor.a : 1.0;
    float falloff = 1.0;
    if ((flags & EffectFlagFalloff) != 0) {
        float4 range = terms.falloff;
        float facing = smoothstep(range.y, range.x, abs(dot(normal, toEye)));
        falloff = mix(max(range.w, 0.0), min(range.z, 1.0), facing);
    }
    float4 glow = terms.baseColor;
    float alphaScale = glow.a * glow.a;
    float3 rgb = base.rgb * tint.rgb * glow.rgb;
    float alpha = base.a * tint.a * falloff * alphaScale;
    if ((flags & EffectFlagPaletteColor) != 0) {
        float2 at = saturate(float2(base.g, tint.g * falloff * glow.r));
        rgb = palette.sample(paletteSampler, at).rgb;
    }
    if ((flags & EffectFlagPaletteAlpha) != 0) {
        float2 at = saturate(float2(base.a, tint.a * falloff * alphaScale));
        alpha = palette.sample(paletteSampler, at).a;
    }
    return float4(rgb * terms.baseColorScale, alpha);
}
