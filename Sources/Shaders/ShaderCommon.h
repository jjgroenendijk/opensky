// Helpers and vertex structs every shader file shares. Vertex layout comes from
// ShaderTypes.h attribute enums and StaticVertexLayout.vertexDescriptor().

#pragma once

#include <metal_raytracing>
#include <metal_stdlib>
#include <simd/simd.h>

#import "ShaderTypes.h"

using namespace metal;

static inline float3 directionalAmbient(float3 normal, constant FrameUniforms &frame)
{
    float3 weights = abs(normal);
    weights /= max(weights.x + weights.y + weights.z, 0.0001);
    float3 x =
        normal.x >= 0.0 ? frame.directionalAmbientPositiveX : frame.directionalAmbientNegativeX;
    float3 y =
        normal.y >= 0.0 ? frame.directionalAmbientPositiveY : frame.directionalAmbientNegativeY;
    float3 z =
        normal.z >= 0.0 ? frame.directionalAmbientPositiveZ : frame.directionalAmbientNegativeZ;
    return x * weights.x + y * weights.y + z * weights.z;
}

static inline float3 pointLighting(
    float3 worldPosition, float3 normal, const device PointLightUniform *lights, uint count)
{
    float3 sum = 0.0;
    for (uint index = 0; index < count; ++index) {
        float3 toLight = lights[index].positionRadius.xyz - worldPosition;
        float distanceToLight = length(toLight);
        float radius = max(lights[index].positionRadius.w, 0.0001);
        float radial = saturate(1.0 - distanceToLight / radius);
        float attenuation = pow(radial, max(lights[index].colorFalloff.w, 0.01));
        float lambert = saturate(dot(normal, toLight / max(distanceToLight, 0.0001)));
        sum += lights[index].colorFalloff.rgb * attenuation * lambert;
    }
    return sum;
}

// Ray-traced sun shadows (docs/rendering/ray-traced-shadows.md). Both constants are
// optional, so every pipeline that does not define them compiles as before.
constant bool rayTracedShadowsValue [[function_constant(FunctionConstantRayTracedShadows)]];
constant bool rayTracedShadows =
    is_function_constant_defined(rayTracedShadowsValue) && rayTracedShadowsValue;
constant bool rayShadowViewValue [[function_constant(FunctionConstantRayShadowView)]];
constant bool rayShadowView =
    is_function_constant_defined(rayShadowViewValue) && rayShadowViewValue;
constant float rayShadowMaxDistance = 16384.0;
constant float rayShadowOriginOffset = 2.0;

// 1 when nothing lies between the point and the sun, else 0.
static inline float rayTracedSunShadow(
    float3 worldPosition,
    float3 normal,
    constant FrameUniforms &frame,
    raytracing::instance_acceleration_structure scene)
{
    raytracing::ray ray(
        worldPosition + normal * rayShadowOriginOffset, -frame.sunDirection, 0.0,
        rayShadowMaxDistance);
    raytracing::intersector<raytracing::instancing> intersector;
    intersector.accept_any_intersection(true);
    auto hit = intersector.intersect(ray, scene);
    return hit.type == raytracing::intersection_type::none ? 1.0 : 0.0;
}

// Receiver-side depth-compare bias (NDC z). Trims residual self-shadow acne
// the raster depth bias leaves behind; kept small to avoid peter-panning.
constant float shadowReceiverBias = 0.0015;

// Which cascade shades a receiver, or -1 when it lies beyond the last one.
// Mirrors ShadowCascadeMath.cascadeIndex verbatim. Shared by sunShadowFactor
// and the shadowCascade debug channel, so the picture the debug view draws is
// the cascade the shading actually used.
static inline int sunShadowCascadeIndex(float3 worldPosition, constant FrameUniforms &frame)
{
    float viewDepth = dot(worldPosition - frame.cameraPosition, frame.cameraForward);
    if (viewDepth > frame.shadowCascadeSplits[ShadowConstantCascadeCount - 1]) {
        return -1;
    }
    int cascade = ShadowConstantCascadeCount - 1;
    for (int slot = ShadowConstantCascadeCount - 1; slot >= 0; --slot) {
        if (viewDepth <= frame.shadowCascadeSplits[slot]) {
            cascade = slot;
        }
    }
    return cascade;
}

// Sun-shadow attenuation for one world-space receiver. Returns 1.0 (lit) when
// shadows are off or the point is outside every cascade map. PCF radius comes
// from FrameUniforms.shadowSampleRadius (0 = 1 tap, 1 = 3x3).
static inline float sunShadowFactor(
    float3 worldPosition,
    constant FrameUniforms &frame,
    depth2d_array<float> shadowMap,
    sampler shadowSampler)
{
    if (frame.shadowsEnabled == 0) {
        return 1.0;
    }
    int cascade = sunShadowCascadeIndex(worldPosition, frame);
    if (cascade < 0) {
        return 1.0;
    }
    float4 clip = frame.shadowViewProjections[cascade] * float4(worldPosition, 1.0);
    float3 ndc = clip.xyz / clip.w;
    if (ndc.x < -1.0 || ndc.x > 1.0 || ndc.y < -1.0 || ndc.y > 1.0 || ndc.z < 0.0 || ndc.z > 1.0) {
        return 1.0;
    }
    float2 uv = ndc.xy * float2(0.5, -0.5) + 0.5;
    float compareDepth = ndc.z - shadowReceiverBias;
    int radius = int(frame.shadowSampleRadius);
    // Low quality: single hardware depth-compare tap, no PCF blur.
    if (radius <= 0) {
        return shadowMap.sample_compare(shadowSampler, uv, cascade, compareDepth);
    }
    float sum = 0.0;
    float taps = 0.0;
    for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
            float2 offset = float2(dx, dy) * frame.shadowInverseResolution;
            sum += shadowMap.sample_compare(shadowSampler, uv + offset, cascade, compareDepth);
            taps += 1.0;
        }
    }
    return sum / taps;
}

static inline float3 applyFog(float3 color, float3 worldPosition, constant FrameUniforms &frame)
{
    if (frame.fogEnabled == 0) {
        return color;
    }
    float distanceToCamera = distance(worldPosition, frame.cameraPosition);
    float range = max(frame.fogDistances.y - frame.fogDistances.x, 0.0001);
    float linear = saturate((distanceToCamera - frame.fogDistances.x) / range);
    float amount = pow(linear, max(frame.fogDistances.z, 0.01)) * frame.fogDistances.w;
    float3 fogColor = mix(frame.fogNearColor, frame.fogFarColor, linear);
    return mix(color, fogColor, saturate(amount));
}

// Render debug views. One function constant gates this block: shipping
// pipelines set it false so the branches fold away, and the debug pipelines
// set it true and pick a channel from FrameUniforms.debugMode. Every pipeline
// must define it, because Metal fails validation on an undefined referenced
// constant (Renderer.specializedFragment).

constant bool debugViewActive [[function_constant(FunctionConstantDebugView)]];

/// Everything the debug channels can read about one fragment. Grouped into a
/// struct so each geometry path passes one value rather than six arguments.
struct DebugSurface
{
    float3 worldPosition;
    float3 normal;
    float2 texcoord;
    /// Mip level the diffuse sampler would pick, or 0 for paths with no texture.
    float mipLevel;
    /// RenderLayerBit this draw belongs to.
    uint layerCategory;
};

/// One colour per sun-shadow cascade, grey past the last one (the region the
/// shading leaves unshadowed).
static inline float3 debugCascadeColor(int cascade)
{
    if (cascade == 0) {
        return float3(0.90, 0.25, 0.20);
    }
    if (cascade == 1) {
        return float3(0.30, 0.80, 0.35);
    }
    if (cascade == 2) {
        return float3(0.25, 0.50, 0.95);
    }
    return float3(0.35, 0.35, 0.35);
}

/// One colour per RenderLayerBit. Unknown values stay magenta, which reads as
/// "a draw reached the pass without a layer" rather than as a plausible layer.
static inline float3 debugLayerColor(uint layer)
{
    switch (layer) {
    case RenderLayerBitStatics:
        return float3(0.85, 0.85, 0.85);
    case RenderLayerBitActors:
        return float3(0.95, 0.55, 0.15);
    case RenderLayerBitDistantLOD:
        return float3(0.45, 0.40, 0.70);
    case RenderLayerBitTerrain:
        return float3(0.40, 0.70, 0.35);
    case RenderLayerBitWater:
        return float3(0.20, 0.55, 0.90);
    case RenderLayerBitSky:
        return float3(0.60, 0.80, 0.95);
    case RenderLayerBitGrass:
        return float3(0.65, 0.85, 0.30);
    case RenderLayerBitParticles:
        return float3(0.95, 0.85, 0.35);
    default:
        return float3(1.0, 0.0, 1.0);
    }
}

/// The debug channel's colour for one fragment. Opaque by design: a debug view
/// answers "what is here", so a cutout's own alpha must not fade the answer.
static inline float4 debugViewColor(constant FrameUniforms &frame, DebugSurface surface)
{
    switch (frame.debugMode) {
    case DebugViewModeWorldNormals:
        return float4(normalize(surface.normal) * 0.5 + 0.5, 1.0);
    case DebugViewModeTextureCoordinates:
        return float4(fract(surface.texcoord), 0.0, 1.0);
    case DebugViewModeMipLevel: {
        // Fine mips cool, coarse mips warm: a surface that jumps to red at
        // arm's length is sampling a mip far below the one it deserves.
        float ramp = saturate(surface.mipLevel / 8.0);
        return float4(mix(float3(0.15, 0.55, 0.95), float3(0.95, 0.30, 0.10), ramp), 1.0);
    }
    case DebugViewModeShadowCascade:
        return float4(debugCascadeColor(sunShadowCascadeIndex(surface.worldPosition, frame)), 1.0);
    case DebugViewModeLayerCategory:
        return float4(debugLayerColor(surface.layerCategory), 1.0);
    default:
        // Wireframe, and any mode a future channel adds before its shader half
        // lands: a flat bright line colour over the cleared attachment.
        return float4(0.85, 0.92, 1.0, 1.0);
    }
}

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal [[attribute(VertexAttributeNormal)]];
    float2 texcoord [[attribute(VertexAttributeTexcoord)]];
    float4 color [[attribute(VertexAttributeColor)]];
} StaticVertexIn;

typedef struct
{
    float4 position [[position]];
    float3 normal;
    float3 worldPosition;
    float2 texcoord;
    float4 color;
} StaticVertexOut;

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal [[attribute(VertexAttributeNormal)]];
    float2 texcoord [[attribute(VertexAttributeTexcoord)]];
    float4 color [[attribute(VertexAttributeColor)]];
    float4 boneWeights [[attribute(VertexAttributeBoneWeights)]];
    ushort4 boneIndices [[attribute(VertexAttributeBoneIndices)]];
} SkinnedVertexIn;

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal [[attribute(VertexAttributeNormal)]];
    float2 texcoord [[attribute(VertexAttributeTexcoord)]];
    float4 color [[attribute(VertexAttributeColor)]];
    float4 boneWeights [[attribute(VertexAttributeBoneWeights)]];
    ushort4 boneIndices [[attribute(VertexAttributeBoneIndices)]];
    float3 morphPositionDelta [[attribute(VertexAttributeMorphPositionDelta)]];
    float3 morphNormalDelta [[attribute(VertexAttributeMorphNormalDelta)]];
} MorphedSkinnedVertexIn;

// Fullscreen triangle output for the sky and the image-space passes.
typedef struct
{
    float4 position [[position]];
    float2 uv;
} SkyVertexOut;

// Pixel-exact fullscreen triangle for passes that read one texel per pixel.
struct TextureReadbackVertexOut
{
    float4 position [[position]];
};
