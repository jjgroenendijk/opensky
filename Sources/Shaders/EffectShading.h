#pragma once

// BSEffectShaderProperty shading: unlit, base color, palette, and falloff. The
// model follows NifSkope's open-source effect shader (sk_effectshader.frag).

#include "ShaderCommon.h"

// A volume in an effect's 2D source slot is sampled at its middle slice. The game's
// behaviour is unconfirmed: no vanilla reference shows such a shape (docs/formats/dds.md).
constant float effectVolumeDepth = 0.5;

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

// Soft effect: the shape fades in over `softDepth` units in front of the scene behind
// it, so smoke and fire cards show no hard line where they cross the ground.
static inline float softEffectFade(
    float2 pixel,
    float3 worldPosition,
    float softDepth,
    constant FrameUniforms &frame,
    depth2d<float> sceneDepth)
{
    bool allowed = (frame.shadingTerms & uint(ShadingTermSoftEffect)) != 0;
    float4 unproject = frame.sceneDepthUnproject;
    if (!allowed || unproject.z < 0.5 || softDepth <= 0.0) {
        return 1.0;
    }
    float stored = sceneDepth.read(uint2(pixel));
    float behind = unproject.y / (stored + unproject.x);
    float own = dot(worldPosition - frame.cameraPosition, frame.cameraForward);
    return saturate((behind - own) / softDepth);
}

struct EffectLightInput
{
    uint flags;
    /// Share of the scene light, 0 to 1.
    float influence;
    float3 worldPosition;
    float3 normal;
    float3 toEye;
    /// rgb the reference's emittance, a 1 when it has one.
    float4 emittance;
};

// What multiplies an effect's colour: the reference's emittance on an
// external-emittance shape, else the scene light on an effect-lit one, else 1.
static inline float3 effectLight(
    EffectLightInput input,
    constant FrameUniforms &frame,
    const device PointLightUniform *pointLights,
    uint pointLightCount)
{
    uint frameTerms = frame.shadingTerms;
    bool external = (input.flags & EffectFlagExternalEmittance) != 0 &&
                    (frameTerms & uint(ShadingTermExternalEmittance)) != 0 &&
                    input.emittance.a > 0.0;
    if (external) {
        return input.emittance.rgb;
    }
    bool lit =
        (input.flags & EffectFlagLit) != 0 && (frameTerms & uint(ShadingTermEffectLighting)) != 0;
    if (!lit) {
        return 1.0;
    }
    // Effect cards are thin and often double-sided, so they take light on the side
    // that faces the eye.
    float3 normal = dot(input.normal, input.toEye) < 0.0 ? -input.normal : input.normal;
    float3 light = baseAmbient(frame) + directionalAmbient(normal, frame) +
                   frame.sunColor * saturate(dot(normal, -frame.sunDirection)) +
                   pointLighting(input.worldPosition, normal, pointLights, pointLightCount);
    return mix(float3(1.0), light, saturate(input.influence));
}
