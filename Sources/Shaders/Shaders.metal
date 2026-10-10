// Static-mesh shaders. Vertex layout comes from ShaderTypes.h attribute
// enums and StaticVertexLayout.vertexDescriptor() (Rendering/RenderMesh.swift).

#include <metal_raytracing>
#include <metal_stdlib>
#include <simd/simd.h>

#import "ShaderTypes.h"

using namespace metal;

static float3 directionalAmbient(float3 normal, constant FrameUniforms &frame)
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

static float3 pointLighting(
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
static float rayTracedSunShadow(
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
static int sunShadowCascadeIndex(float3 worldPosition, constant FrameUniforms &frame)
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
static float sunShadowFactor(
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

static float3 applyFog(float3 color, float3 worldPosition, constant FrameUniforms &frame)
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
static float3 debugCascadeColor(int cascade)
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
static float3 debugLayerColor(uint layer)
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
static float4 debugViewColor(constant FrameUniforms &frame, DebugSurface surface)
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

// Exterior sky: fullscreen triangle. With weather active the sky uses the
// CPU-blended WTHR palette in FrameUniforms; otherwise the procedural
// time-of-day palette below.

typedef struct
{
    float4 position [[position]];
    float2 uv;
} SkyVertexOut;

vertex SkyVertexOut skyVertex(uint vertexID [[vertex_id]])
{
    float2 positions[3] = {float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)};
    SkyVertexOut out;
    out.position = float4(positions[vertexID], 1.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

// The sun sits along the same direction that lights the scene. The pixel's
// view ray is rebuilt from the camera basis, so the disc stays round at any
// aspect ratio. Returns (disc, glow), both zero once the sun is below the horizon.
static float2 skySunDiscAndGlow(SkyVertexOut in, constant FrameUniforms &frame)
{
    float4 rightClip =
        frame.viewProjectionMatrix * float4(frame.cameraForward + frame.cameraRight, 0.0);
    float4 upClip = frame.viewProjectionMatrix * float4(frame.cameraForward + frame.cameraUp, 0.0);
    float2 ndc = in.uv * 2.0 - 1.0;
    float tanX = abs(rightClip.x) > 1e-5 ? rightClip.w / rightClip.x : 1.0;
    float tanY = abs(upClip.y) > 1e-5 ? upClip.w / upClip.y : 1.0;
    float3 ray = normalize(
        frame.cameraForward + frame.cameraRight * (ndc.x * tanX) + frame.cameraUp * (ndc.y * tanY));
    float3 towardSun = -normalize(frame.sunDirection);
    float aboveHorizon = smoothstep(-0.05, 0.05, towardSun.z);
    float angle = acos(clamp(dot(ray, towardSun), -1.0, 1.0));
    float disc = (1.0 - smoothstep(0.016, 0.02, angle)) * aboveHorizon;
    float glow = exp(-angle * 12.0) * aboveHorizon;
    return float2(disc, glow);
}

// Weather sky: horizon -> sky-lower -> sky-upper vertical gradient, with the
// sun disc and glow tinted by the weather sun and sun-glare colours.
static float4 weatherSky(SkyVertexOut in, constant FrameUniforms &frame)
{
    float3 lower =
        mix(frame.weatherHorizonColor, frame.weatherSkyLowerColor, smoothstep(0.0, 0.5, in.uv.y));
    float3 upper =
        mix(frame.weatherSkyLowerColor, frame.weatherSkyUpperColor, smoothstep(0.5, 1.0, in.uv.y));
    float3 color = in.uv.y < 0.5 ? lower : upper;

    float2 sun = skySunDiscAndGlow(in, frame);
    float3 tint =
        frame.weatherSunColor /
        max(max3(frame.weatherSunColor.r, frame.weatherSunColor.g, frame.weatherSunColor.b), 1e-3);
    color += frame.weatherGlareColor * sun.y * 0.5;
    color = mix(color, mix(tint, float3(1.0), 0.6), sun.x);
    return float4(color, 1.0);
}

fragment float4 skyFragment(
    SkyVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]])
{
    float hour = fmod(frame.timeOfDayHours + 24.0, 24.0);
    if (frame.weatherSkyEnabled != 0) {
        return weatherSky(in, frame);
    }
    float sunrise = smoothstep(5.0, 8.0, hour);
    float sunset = 1.0 - smoothstep(18.0, 21.0, hour);
    float daylight = sunrise * sunset;
    float dawnDistance = min(abs(hour - 6.0), abs(hour - 19.0));
    float twilight = exp(-0.5 * pow(dawnDistance / 1.2, 2.0));

    float3 nightUpper = float3(0.008, 0.015, 0.045);
    float3 dayUpper = float3(0.10, 0.34, 0.72);
    float3 nightHorizon = float3(0.025, 0.035, 0.075);
    float3 dayHorizon = float3(0.58, 0.74, 0.88);
    float3 warmHorizon = float3(0.95, 0.33, 0.12);
    float3 upper = mix(nightUpper, dayUpper, daylight);
    float3 horizon = mix(nightHorizon, dayHorizon, daylight);
    horizon = mix(horizon, warmHorizon, saturate(twilight * 0.7));
    float height = smoothstep(0.05, 0.92, in.uv.y);
    float3 color = mix(horizon, upper, height);

    float2 sun = skySunDiscAndGlow(in, frame);
    color += float3(1.0, 0.72, 0.36) * sun.y * 0.22;
    color = mix(color, float3(1.0, 0.95, 0.82), sun.x);
    return float4(color, 1.0);
}

// Weather cloud layers on the dome shapes of meshes\sky\clouds.nif. The dome
// follows the camera and draws behind everything, after the sky gradient.

typedef struct
{
    float4 position [[position]];
    float4 color;
    float2 texcoord;
} CloudVertexOut;

vertex CloudVertexOut cloudVertex(
    uint vertexID [[vertex_id]],
    const device CloudVertex *vertices [[buffer(BufferIndexVertices)]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant CloudLayerUniforms &layer [[buffer(BufferIndexDrawUniforms)]])
{
    CloudVertex source = vertices[vertexID];
    float4 clip =
        frame.viewProjectionMatrix * float4(frame.cameraPosition + source.position.xyz, 1.0);
    // Any depth inside the clip range: the dome draws with no depth test.
    clip.z = clip.w * 0.5;
    CloudVertexOut out;
    out.position = clip;
    out.color = source.color;
    out.texcoord = source.texcoord + layer.uvOffset;
    return out;
}

fragment float4 cloudFragment(
    CloudVertexOut in [[stage_in]],
    constant CloudLayerUniforms &layer [[buffer(BufferIndexDrawUniforms)]],
    texture2d<float> cloudMap [[texture(TextureIndexDiffuse)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    float4 texel = cloudMap.sample(trilinear, in.texcoord);
    // The dome's vertex colours are (1, 0, 0, a): only the alpha, an edge fade, is used.
    float alpha = texel.a * layer.colorAlpha.a * in.color.a;
    return float4(texel.rgb * layer.colorAlpha.rgb, alpha);
}

// Static-mesh path: diffuse * (directional sun + ambient),
// vertex color as tint (Skyrim bakes AO there). Alpha-test pipeline variant
// selected via function constant so opaque draws pay nothing for it.

constant bool alphaTestEnabled [[function_constant(FunctionConstantAlphaTest)]];
// Optional: only the blended static pipeline defines it. The others write alpha 1.
constant bool alphaBlendValue [[function_constant(FunctionConstantAlphaBlend)]];
constant bool alphaBlendEnabled = is_function_constant_defined(alphaBlendValue) && alphaBlendValue;

// BSEffectShaderProperty shading: unlit, base color, palette, and falloff. The
// model follows NifSkope's open-source effect shader (sk_effectshader.frag).
static float4 effectShade(
    float4 base,
    float4 vertexColor,
    float3 normal,
    float3 toEye,
    constant DrawUniforms &draw,
    texture2d<float> palette)
{
    constexpr sampler paletteSampler(filter::linear, address::clamp_to_edge);
    uint flags = draw.effectFlags;
    float4 tint = (flags & EffectFlagVertexColors) != 0 ? vertexColor : float4(1.0);
    tint.a = (flags & EffectFlagVertexAlpha) != 0 ? vertexColor.a : 1.0;
    float falloff = 1.0;
    if ((flags & EffectFlagFalloff) != 0) {
        float4 range = draw.effectFalloff;
        float facing = smoothstep(range.y, range.x, abs(dot(normal, toEye)));
        falloff = mix(max(range.w, 0.0), min(range.z, 1.0), facing);
    }
    float4 glow = draw.effectBaseColor;
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
    return float4(rgb * draw.effectBaseColorScale, alpha);
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

// Instanced: matrices come from the per-instance transform
// array, bound at the draw group's base offset — instance_id starts at 0
// per draw call, so it indexes straight into the group's visible instances.
// Shared by the opaque and alpha-test pipeline variants (the function
// constant only specializes the fragment side).
vertex StaticVertexOut staticMeshVertex(
    StaticVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant DrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]])
{
    StaticVertexOut out;
    const device InstanceTransform &instance = instances[instanceID];
    float4 world = instance.modelMatrix * float4(in.position, 1.0);
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (instance.normalMatrix * float4(in.normal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    out.color = in.color;
    return out;
}

// Bind-pose hardware skinning. Bone matrices use Gamebryo's documented
// rootParentToSkin * currentBoneToRootParent * skinToBoneBind composition;
// animation will replace this immutable per-mesh buffer in milestone 6.
vertex StaticVertexOut skinnedMeshVertex(
    SkinnedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant DrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device matrix_float4x4 *bones [[buffer(BufferIndexBoneMatrices)]])
{
    float4 skinPosition = 0.0;
    float3 skinNormal = 0.0;
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        matrix_float4x4 bone = bones[in.boneIndices[influence]];
        skinPosition += weight * (bone * float4(in.position, 1.0));
        skinNormal += weight * (bone * float4(in.normal, 0.0)).xyz;
    }
    const device InstanceTransform &instance = instances[instanceID];
    float4 world = instance.modelMatrix * skinPosition;
    StaticVertexOut out;
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (instance.normalMatrix * float4(skinNormal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    out.color = in.color;
    return out;
}

vertex StaticVertexOut morphedSkinnedMeshVertex(
    MorphedSkinnedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant DrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device matrix_float4x4 *bones [[buffer(BufferIndexBoneMatrices)]])
{
    float4 skinPosition = 0.0;
    float3 skinNormal = 0.0;
    float3 position = in.position + in.morphPositionDelta;
    float3 normal = in.normal + in.morphNormalDelta;
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        matrix_float4x4 bone = bones[in.boneIndices[influence]];
        skinPosition += weight * (bone * float4(position, 1.0));
        skinNormal += weight * (bone * float4(normal, 0.0)).xyz;
    }
    const device InstanceTransform &instance = instances[instanceID];
    float4 world = instance.modelMatrix * skinPosition;
    StaticVertexOut out;
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (instance.normalMatrix * float4(skinNormal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    out.color = in.color;
    return out;
}

fragment float4 staticMeshFragment(
    StaticVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant DrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device PointLightUniform *pointLights [[buffer(BufferIndexPointLights)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    texture2d<float> effectPalette [[texture(TextureIndexEffectPalette)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]],
    raytracing::instance_acceleration_structure rayScene
    [[buffer(BufferIndexRayScene), function_constant(rayTracedShadows)]])
{
    float4 diffuse = diffuseMap.sample(trilinear, in.texcoord);
    bool isEffect = (draw.effectFlags & EffectFlagEnabled) != 0;
    float4 effect = 0.0;
    float alpha = diffuse.a * in.color.a * draw.materialAlpha;
    if (isEffect) {
        float3 toEye = normalize(frame.cameraPosition - in.worldPosition);
        effect = effectShade(diffuse, in.color, normalize(in.normal), toEye, draw, effectPalette);
        alpha = effect.a * draw.materialAlpha;
    }
    if (alphaTestEnabled && alpha < draw.alphaThreshold) {
        discard_fragment();
    }
    if (debugViewActive) {
        DebugSurface surface = {
            in.worldPosition, in.normal, in.texcoord,
            diffuseMap.calculate_unclamped_lod(trilinear, in.texcoord), draw.layerCategory};
        return debugViewColor(frame, surface);
    }
    if (isEffect) {
        float3 shaded = applyFog(effect.rgb, in.worldPosition, frame);
        return float4(shaded, alphaBlendEnabled ? alpha : 1.0);
    }
    float3 normal = normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float shadow = draw.receivesShadows != 0
                       ? sunShadowFactor(in.worldPosition, frame, shadowMap, shadowSampler)
                       : 1.0;
    if (rayTracedShadows) {
        float traced = draw.receivesShadows != 0
                           ? rayTracedSunShadow(in.worldPosition, normal, frame, rayScene)
                           : 1.0;
        if (rayShadowView) {
            return float4(float3(traced), 1.0);
        }
        shadow = min(shadow, traced);
    }
    float3 illumination =
        frame.sunColor * lambert * shadow + frame.ambientColor + directionalAmbient(normal, frame) +
        pointLighting(in.worldPosition, normal, pointLights, draw.pointLightCount);
    float3 lit = diffuse.rgb * in.color.rgb * illumination;
    // Opaque: alpha only gates the test above. The frame is premultiplied, so
    // a lower alpha would show as white or black. The blended pass blends it.
    return float4(applyFog(lit, in.worldPosition, frame), alphaBlendEnabled ? alpha : 1.0);
}

// GRAS path: same material/lighting model as cutout static meshes, with one
// placement per GPU instance. LAND tint is per instance. Weather wind bends
// only upper vertices; wave period + stable phase keep neighboring blades
// asynchronous. Distance fade multiplies alpha before cutoff.

typedef struct
{
    float4 position [[position]];
    float3 normal;
    float3 worldPosition;
    float2 texcoord;
    float4 color;
    float distanceFade;
} GrassVertexOut;

/// Wind, tint, and fade of one grass vertex; the vertex and mesh paths share it.
static GrassVertexOut grassVertexOut(
    float3 position,
    float3 normal,
    float2 texcoord,
    float4 color,
    const device InstanceTransform &instance,
    constant FrameUniforms &frame,
    constant GrassDrawUniforms &draw)
{
    float4 world = instance.modelMatrix * float4(position, 1.0);
    float height = saturate((position.z - draw.modelMinimumZ) * draw.inverseModelHeight);
    float wavePeriod = max(instance.grassParameters.x, 0.1);
    float phase = frame.animationTime / wavePeriod + instance.grassParameters.y;
    float oscillation = sin(phase * 6.28318530718);
    float bend = height * height * (72.0 + 24.0 * oscillation);
    world.xy += frame.grassWind * bend;

    GrassVertexOut out;
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (instance.normalMatrix * float4(normal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = texcoord * draw.uvScale + draw.uvOffset;
    out.color = color * instance.instanceColor;
    float fadeWidth = max(frame.grassFadeDistances.y - frame.grassFadeDistances.x, 1.0);
    out.distanceFade = saturate(
        (frame.grassFadeDistances.y - distance(world.xyz, frame.cameraPosition)) / fadeWidth);
    return out;
}

vertex GrassVertexOut grassVertex(
    StaticVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant GrassDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]])
{
    return grassVertexOut(
        in.position, in.normal, in.texcoord, in.color, instances[instanceID], frame, draw);
}

// Mesh-shader grass (docs/rendering/mesh-shader-grass.md). One object threadgroup is one
// SIMD group: each lane tests one instance-meshlet pair and the group launches a mesh
// threadgroup per pair it keeps. The mesh threadgroup writes that meshlet's triangles.

constant uint kGrassMeshletsPerObjectGroup = 32;
constant uint kGrassMeshletMaxVertices = 64;
constant uint kGrassMeshletMaxTriangles = 64;

/// Kept pairs, as `instance * meshletCount + meshlet`.
typedef struct
{
    uint pairs[kGrassMeshletsPerObjectGroup];
} GrassMeshletPayload;

/// The interleaved static vertex (StaticVertexLayout, 48 bytes), read without stage_in.
typedef struct
{
    packed_float3 position;
    packed_float3 normal;
    float2 texcoord;
    float4 color;
} GrassMeshVertex;

static bool grassMeshletVisible(
    MeshletBounds meshlet,
    const device InstanceTransform &instance,
    constant FrameUniforms &frame,
    constant GrassMeshUniforms &mesh)
{
    float3 center = (instance.modelMatrix * float4(meshlet.centerRadius.xyz, 1.0)).xyz;
    float scale =
        max(length(instance.modelMatrix[0].xyz),
            max(length(instance.modelMatrix[1].xyz), length(instance.modelMatrix[2].xyz)));
    float radius = meshlet.centerRadius.w * scale + mesh.swayPadding;
    for (uint plane = 0; plane < 6; plane++) {
        float4 p = mesh.frustumPlanes[plane];
        if (dot(p.xyz, center) + p.w < -radius) {
            return false;
        }
    }
    if (mesh.cullBackfaces == 0 || meshlet.coneAxisCutoff.w <= -1.0) {
        return true;
    }
    float3 axis = normalize((instance.normalMatrix * float4(meshlet.coneAxisCutoff.xyz, 0)).xyz);
    float3 toCenter = center - frame.cameraPosition;
    return dot(toCenter, axis) < meshlet.coneAxisCutoff.w * length(toCenter) + radius;
}

[[object]] void grassMeshletObject(
    object_data GrassMeshletPayload &payload [[payload]],
    mesh_grid_properties grid,
    uint group [[threadgroup_position_in_grid]],
    uint lane [[thread_index_in_threadgroup]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant GrassMeshUniforms &mesh [[buffer(BufferIndexGrassMeshUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device MeshletBounds *meshlets [[buffer(BufferIndexMeshlets)]],
    device atomic_uint *counters [[buffer(BufferIndexMeshletCounters)]])
{
    uint pair = group * kGrassMeshletsPerObjectGroup + lane;
    bool tested = pair < mesh.instanceCount * mesh.meshletCount;
    bool visible = tested && grassMeshletVisible(
                                 meshlets[pair % mesh.meshletCount],
                                 instances[pair / mesh.meshletCount], frame, mesh);
    uint slot = simd_prefix_exclusive_sum(uint(visible));
    uint kept = simd_sum(uint(visible));
    uint testedCount = simd_sum(uint(tested));
    if (visible) {
        payload.pairs[slot] = pair;
    }
    if (lane == 0) {
        grid.set_threadgroups_per_grid(uint3(kept, 1, 1));
        atomic_fetch_add_explicit(&counters[mesh.counterBase], testedCount, memory_order_relaxed);
        atomic_fetch_add_explicit(&counters[mesh.counterBase + 1], kept, memory_order_relaxed);
    }
}

using GrassMeshletOutput = metal::mesh<
    GrassVertexOut,
    void,
    kGrassMeshletMaxVertices,
    kGrassMeshletMaxTriangles,
    topology::triangle>;

[[mesh]] void grassMeshletMesh(
    GrassMeshletOutput output,
    const object_data GrassMeshletPayload &payload [[payload]],
    uint group [[threadgroup_position_in_grid]],
    uint lane [[thread_index_in_threadgroup]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant GrassDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    constant GrassMeshUniforms &mesh [[buffer(BufferIndexGrassMeshUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device GrassMeshVertex *vertices [[buffer(BufferIndexVertices)]],
    const device MeshletBounds *meshlets [[buffer(BufferIndexMeshlets)]],
    const device uint *vertexIndices [[buffer(BufferIndexMeshletVertices)]],
    const device uchar *triangles [[buffer(BufferIndexMeshletTriangles)]])
{
    uint pair = payload.pairs[group];
    MeshletBounds meshlet = meshlets[pair % mesh.meshletCount];
    const device InstanceTransform &instance = instances[pair / mesh.meshletCount];
    if (lane == 0) {
        output.set_primitive_count(meshlet.triangleCount);
    }
    if (lane < meshlet.vertexCount) {
        uint vertexIndex = min(vertexIndices[meshlet.vertexOffset + lane], mesh.vertexCount - 1);
        GrassMeshVertex v = vertices[vertexIndex];
        output.set_vertex(
            lane,
            grassVertexOut(
                float3(v.position), float3(v.normal), v.texcoord, v.color, instance, frame, draw));
    }
    if (lane < meshlet.triangleCount) {
        uint base = (meshlet.triangleOffset + lane) * 3;
        output.set_index(lane * 3, triangles[base]);
        output.set_index(lane * 3 + 1, triangles[base + 1]);
        output.set_index(lane * 3 + 2, triangles[base + 2]);
    }
}

fragment float4 grassFragment(
    GrassVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant GrassDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]])
{
    float4 diffuse = diffuseMap.sample(trilinear, in.texcoord);
    // Grass vertex alpha is the wind weight, 0 at the root, not opacity.
    float alpha = diffuse.a * draw.materialAlpha * in.distanceFade;
    if (alpha < draw.alphaThreshold) {
        discard_fragment();
    }
    if (debugViewActive) {
        DebugSurface surface = {
            in.worldPosition, in.normal, in.texcoord,
            diffuseMap.calculate_unclamped_lod(trilinear, in.texcoord), uint(RenderLayerBitGrass)};
        return debugViewColor(frame, surface);
    }
    float3 normal = normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float shadow = draw.receivesShadows != 0
                       ? sunShadowFactor(in.worldPosition, frame, shadowMap, shadowSampler)
                       : 1.0;
    float3 illumination =
        frame.sunColor * lambert * shadow + frame.ambientColor + directionalAmbient(normal, frame);
    float3 lit = diffuse.rgb * in.color.rgb * illumination;
    // Opaque: alpha only gates the test above. The frame is premultiplied, so
    // a lower alpha would show as white or black.
    return float4(applyFog(lit, in.worldPosition, frame), 1.0);
}

// Terrain splat path (docs/rendering/scene-drawing.md): per-quadrant draw blends the BTXT
// base diffuse with up to TerrainConstantMaxLayers ATXT layer diffuses by
// per-vertex VTXT opacities (UESP LAND: VTXT holds a 0.0-1.0 opacity per
// painted vertex of the 17x17 quadrant grid). Weights arrive as a second
// vertex stream (TerrainVertexLayout, Rendering/RenderMesh.swift). Lighting
// matches staticMeshFragment so terrain shades like static meshes.

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal [[attribute(VertexAttributeNormal)]];
    float2 texcoord [[attribute(VertexAttributeTexcoord)]];
    float4 color [[attribute(VertexAttributeColor)]];
    float4 weights0 [[attribute(VertexAttributeLayerWeights0)]];
    float4 weights1 [[attribute(VertexAttributeLayerWeights1)]];
} TerrainVertexIn;

typedef struct
{
    float4 position [[position]];
    float3 normal;
    float3 worldPosition;
    float2 texcoord;
    float4 color;
    float4 weights0;
    float4 weights1;
    /// World direction of +u, east (TerrainMeshBuilder UVs). +v is north.
    float3 tangent;
} TerrainVertexOut;

vertex TerrainVertexOut terrainVertex(
    TerrainVertexIn in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant TerrainDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]])
{
    TerrainVertexOut out;
    float4 world = draw.modelMatrix * float4(in.position, 1.0);
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (draw.normalMatrix * float4(in.normal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    out.color = in.color;
    out.weights0 = in.weights0;
    out.weights1 = in.weights1;
    out.tangent = (draw.modelMatrix * float4(1.0, 0.0, 0.0, 0.0)).xyz;
    return out;
}

/// Tangent-space normal from a TX01 texel. Z is rebuilt from XY, so a two-channel
/// map works too. Green points along +v (measured on the vanilla maps, docs/engine/terrain.md).
static float2 terrainNormalXY(float4 texel)
{
    return texel.rg * 2.0 - 1.0;
}

/// The blended layer normals bend the vertex normal. East is made orthogonal to it,
/// and north follows from the cross product.
static float3 terrainShadingNormal(TerrainVertexOut in, float2 blendedXY)
{
    float3 vertexNormal = normalize(in.normal);
    float3 tangent = normalize(in.tangent - vertexNormal * dot(in.tangent, vertexNormal));
    float3 bitangent = cross(vertexNormal, tangent);
    float z = sqrt(saturate(1.0 - dot(blendedXY, blendedXY)));
    return normalize(tangent * blendedXY.x + bitangent * blendedXY.y + vertexNormal * z);
}

fragment float4 terrainFragment(
    TerrainVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant TerrainDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device PointLightUniform *pointLights [[buffer(BufferIndexPointLights)]],
    texture2d<float> baseMap [[texture(TextureIndexDiffuse)]],
    array<texture2d<float>, TerrainConstantMaxLayers> layerMaps
    [[texture(TextureIndexTerrainLayer0)]],
    texture2d<float> baseNormalMap [[texture(TextureIndexTerrainBaseNormal)]],
    array<texture2d<float>, TerrainConstantMaxLayers> layerNormalMaps
    [[texture(TextureIndexTerrainLayerNormal0)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]],
    raytracing::instance_acceleration_structure rayScene
    [[buffer(BufferIndexRayScene), function_constant(rayTracedShadows)]])
{
    if (debugViewActive) {
        DebugSurface surface = {
            in.worldPosition, in.normal, in.texcoord,
            baseMap.calculate_unclamped_lod(trilinear, in.texcoord), uint(RenderLayerBitTerrain)};
        return debugViewColor(frame, surface);
    }
    // Start opaque base, then lerp each layer in over the running color in
    // ATXT layer order. Straight lerp by VTXT opacity is the plain reading of
    // the spec; the exact vanilla blend curve is UNCONFIRMED.
    float3 albedo = baseMap.sample(trilinear, in.texcoord).rgb;
    float weights[TerrainConstantMaxLayers] = {in.weights0.x, in.weights0.y, in.weights0.z,
                                               in.weights0.w, in.weights1.x, in.weights1.y,
                                               in.weights1.z, in.weights1.w};
    bool normalMaps = draw.normalMapsEnabled != 0;
    float2 normalXY =
        normalMaps ? terrainNormalXY(baseNormalMap.sample(trilinear, in.texcoord)) : float2(0.0);
    uint count = min(draw.layerCount, uint(TerrainConstantMaxLayers));
    for (uint layer = 0; layer < count; ++layer) {
        float weight = saturate(weights[layer]);
        float3 layerColor = layerMaps[layer].sample(trilinear, in.texcoord).rgb;
        albedo = mix(albedo, layerColor, weight);
        if (normalMaps) {
            float4 texel = layerNormalMaps[layer].sample(trilinear, in.texcoord);
            normalXY = mix(normalXY, terrainNormalXY(texel), weight);
        }
    }
    float3 normal = normalMaps ? terrainShadingNormal(in, normalXY) : normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float shadow = sunShadowFactor(in.worldPosition, frame, shadowMap, shadowSampler);
    if (rayTracedShadows) {
        float traced = rayTracedSunShadow(in.worldPosition, normalize(in.normal), frame, rayScene);
        if (rayShadowView) {
            return float4(float3(traced), 1.0);
        }
        shadow = min(shadow, traced);
    }
    float3 illumination =
        frame.sunColor * lambert * shadow + frame.ambientColor + directionalAmbient(normal, frame) +
        pointLighting(in.worldPosition, normal, pointLights, draw.pointLightCount);
    float3 lit = albedo * in.color.rgb * illumination;
    return float4(applyFog(lit, in.worldPosition, frame), 1.0);
}

// Water: WATR colors and shading over three scrolling noise layers. The game samples
// noise textures; OpenSky sums sine waves with the same wind, tile size, and slope
// (docs/rendering/water.md). Scene depth, when bound, sets the see-through depth.

typedef struct
{
    float4 position [[position]];
    float3 worldPosition;
} WaterVertexOut;

vertex WaterVertexOut waterVertex(
    StaticVertexIn in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant WaterDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]])
{
    WaterVertexOut out;
    float4 world = draw.modelMatrix * float4(in.position, 1.0);
    out.position = frame.viewProjectionMatrix * world;
    out.worldPosition = world.xyz;
    return out;
}

// Three waves per layer, spread around the wind direction, so no single crest repeats.
static float3 waterNormal(float2 xy, float time, constant WaterDrawUniforms &draw)
{
    constexpr float tau = 6.2831853;
    float2 slope = 0.0;
    float2 flowing = xy - draw.flowVelocity * time;
    for (int layer = 0; layer < 3; ++layer) {
        float tile = max(draw.uvScales[layer], 50.0);
        float strength = draw.amplitudes[layer] * 0.08;
        for (int wave = 0; wave < 3; ++wave) {
            float angle = draw.windDirections[layer] + (float(wave) - 1.0) * 0.6;
            float2 direction = float2(cos(angle), sin(angle));
            float waveLength = tile * (1.0 - 0.3 * float(wave));
            float phase = tau * (dot(direction, flowing) / waveLength -
                                 draw.windSpeeds[layer] * time * (1.0 + 0.4 * float(wave)));
            slope += direction * (strength * cos(phase));
        }
    }
    return normalize(float3(-slope, 1.0));
}

fragment float4 waterFragment(
    WaterVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant WaterDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    depth2d<float> sceneDepth [[texture(TextureIndexWaterDepth)]])
{
    if (debugViewActive) {
        // A water plane is flat and untextured, so the normal is the plane's
        // own up and there is no meaningful texcoord or mip level to report.
        DebugSurface surface = {
            in.worldPosition, float3(0.0, 0.0, 1.0), float2(0.0), 0.0, uint(RenderLayerBitWater)};
        return debugViewColor(frame, surface);
    }
    float3 toCamera = frame.cameraPosition - in.worldPosition;
    float3 view = normalize(toCamera);
    float3 normal = waterNormal(in.worldPosition.xy, frame.animationTime, draw);
    if (view.z < 0.0) {
        normal = -normal;
    }

    // Water column under this pixel, straight down and along the view ray. With no
    // scene depth, a middle depth keeps the surface half see-through.
    float columnDepth = draw.depthAndSun.z * 0.7;
    float rayDepth = columnDepth;
    if (draw.depthAndSun.w > 0.5) {
        float stored = sceneDepth.read(uint2(in.position.xy));
        float behind = draw.depthUnproject.y / (stored + draw.depthUnproject.x);
        float facing = max(dot(-view, frame.cameraForward), 0.05);
        float surfaceDepth = dot(-toCamera, frame.cameraForward);
        rayDepth = max(behind - surfaceDepth, 0.0) / facing;
        columnDepth = rayDepth * abs(view.z);
    }
    float deepness = smoothstep(
        draw.depthAndSun.y, max(draw.depthAndSun.z, draw.depthAndSun.y + 1.0), columnDepth);
    float3 body = mix(draw.shallowColor, draw.deepColor, deepness);

    float baseReflect = clamp(draw.surface.y, 0.02, 1.0);
    float fresnel = baseReflect + (1.0 - baseReflect) * pow(1.0 - saturate(dot(normal, view)), 5.0);
    float reflection = saturate(fresnel * draw.surface.z);
    float3 sky = mix(draw.reflectionColor, frame.fogFarColor, 0.35);
    float3 color = mix(body * (frame.ambientColor + frame.sunColor * 0.6), sky, reflection);

    float3 mirrored = reflect(-view, normal);
    float sunAlign = saturate(dot(mirrored, -frame.sunDirection));
    float specular = pow(sunAlign, max(draw.surface.w * 0.25, 8.0)) * draw.depthAndSun.x;
    color += frame.sunColor * specular;

    // Shallow water shows the ground through it; deep or edge-on water hides it.
    float seeThrough = 1.0 - smoothstep(0.0, max(draw.depthAndSun.z, 1.0) * 2.0, rayDepth);
    float bodyAlpha = mix(1.0, draw.surface.x, seeThrough);
    float alpha = saturate(max(bodyAlpha, reflection) + specular);
    return float4(applyFog(color, in.worldPosition, frame), alpha);
}

// CPU particle path: six vertex_id corners per instance. Camera basis comes
// from FrameUniforms, so every quad remains billboarded without CPU rebuild.

typedef struct
{
    float4 position [[position]];
    float3 worldPosition;
    float2 texcoord;
    float4 color;
} ParticleVertexOut;

vertex ParticleVertexOut particleVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    const device ParticleInstance *particles [[buffer(BufferIndexParticleInstances)]])
{
    constexpr float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1),
                                   float2(-1, 1),  float2(1, -1), float2(1, 1)};
    const device ParticleInstance &particle = particles[instanceID];
    float2 corner = corners[vertexID];
    float3 world =
        particle.positionSize.xyz +
        (frame.cameraRight * corner.x + frame.cameraUp * corner.y) * particle.positionSize.w;
    ParticleVertexOut out;
    out.position = frame.viewProjectionMatrix * float4(world, 1.0);
    out.worldPosition = world;
    float2 atlasUV = corner * 0.5 + 0.5;
    out.texcoord = particle.uvRect.xy + atlasUV * particle.uvRect.zw;
    out.color = particle.color;
    return out;
}

fragment float4 particleFragment(
    ParticleVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    texture2d<float> sourceMap [[texture(TextureIndexDiffuse)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    float4 sample = sourceMap.sample(trilinear, in.texcoord) * in.color;
    if (sample.a <= 0.002) {
        discard_fragment();
    }
    return float4(applyFog(sample.rgb, in.worldPosition, frame), sample.a);
}

// Decals (docs/rendering/decals.md): a flat quad on the struck surface, lit by the
// sun and ambient with the surface normal, drawn after the opaque scene with a depth
// bias so it wins the depth test against the surface under it.

typedef struct
{
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 texcoord;
    float4 color;
} DecalVertexOut;

vertex DecalVertexOut decalVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    const device DecalInstance *decals [[buffer(BufferIndexParticleInstances)]])
{
    constexpr float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1),
                                   float2(-1, 1),  float2(1, -1), float2(1, 1)};
    const device DecalInstance &decal = decals[instanceID];
    float2 corner = corners[vertexID];
    float3 world = decal.center.xyz + decal.axisU.xyz * corner.x + decal.axisV.xyz * corner.y;
    DecalVertexOut out;
    out.position = frame.viewProjectionMatrix * float4(world, 1.0);
    out.worldPosition = world;
    out.normal = cross(decal.axisU.xyz, decal.axisV.xyz);
    out.texcoord =
        decal.uvRect.xy + float2(corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5) * decal.uvRect.zw;
    out.color = decal.color;
    return out;
}

fragment float4 decalFragment(
    DecalVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]])
{
    float4 diffuse = diffuseMap.sample(trilinear, in.texcoord) * in.color;
    if (diffuse.a <= 0.002) {
        discard_fragment();
    }
    float3 normal = normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float shadow = sunShadowFactor(in.worldPosition, frame, shadowMap, shadowSampler);
    float3 illumination =
        frame.sunColor * lambert * shadow + frame.ambientColor + directionalAmbient(normal, frame);
    return float4(applyFog(diffuse.rgb * illumination, in.worldPosition, frame), diffuse.a);
}

// Sun-shadow depth pre-pass: each caster renders into one cascade slice,
// depth only. Static and skinned casters take their model matrix from the
// instance/bone path, terrain from ShadowDrawUniforms.modelMatrix. Only the
// alpha-test variant has a fragment, for the diffuse alpha discard.

typedef struct
{
    float4 position [[position]];
    float2 texcoord;
} ShadowVertexOut;

vertex ShadowVertexOut shadowStaticVertex(
    StaticVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant ShadowDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]])
{
    ShadowVertexOut out;
    float4 world = instances[instanceID].modelMatrix * float4(in.position, 1.0);
    out.position = draw.lightViewProjection * world;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    return out;
}

vertex ShadowVertexOut shadowSkinnedVertex(
    SkinnedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant ShadowDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device matrix_float4x4 *bones [[buffer(BufferIndexBoneMatrices)]])
{
    float4 skinPosition = 0.0;
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        skinPosition += weight * (bones[in.boneIndices[influence]] * float4(in.position, 1.0));
    }
    ShadowVertexOut out;
    float4 world = instances[instanceID].modelMatrix * skinPosition;
    out.position = draw.lightViewProjection * world;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    return out;
}

vertex ShadowVertexOut shadowMorphedSkinnedVertex(
    MorphedSkinnedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant ShadowDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device matrix_float4x4 *bones [[buffer(BufferIndexBoneMatrices)]])
{
    float4 skinPosition = 0.0;
    float3 position = in.position + in.morphPositionDelta;
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        skinPosition += weight * (bones[in.boneIndices[influence]] * float4(position, 1.0));
    }
    ShadowVertexOut out;
    float4 world = instances[instanceID].modelMatrix * skinPosition;
    out.position = draw.lightViewProjection * world;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    return out;
}

vertex ShadowVertexOut shadowTerrainVertex(
    StaticVertexIn in [[stage_in]],
    constant ShadowDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]])
{
    ShadowVertexOut out;
    float4 world = draw.modelMatrix * float4(in.position, 1.0);
    out.position = draw.lightViewProjection * world;
    out.texcoord = in.texcoord;
    return out;
}

fragment void shadowAlphaTestFragment(
    ShadowVertexOut in [[stage_in]],
    constant ShadowDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    float alpha = diffuseMap.sample(trilinear, in.texcoord).a;
    if (alpha < draw.alphaThreshold) {
        discard_fragment();
    }
}

// Depth-tested world-space debug overlay. Triangles and line segments share
// one vertex/color pipeline; CPU submission groups the two topologies into
// adjacent ranges of the same per-frame upload.

typedef struct
{
    float4 position [[position]];
    float4 color;
} OverlayVertexOut;

vertex OverlayVertexOut overlayVertex(
    uint vertexID [[vertex_id]],
    const device OverlayVertex *vertices [[buffer(BufferIndexOverlayVertices)]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]])
{
    const device OverlayVertex &in = vertices[vertexID];
    OverlayVertexOut out;
    out.position = frame.viewProjectionMatrix * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 overlayFragment(OverlayVertexOut in [[stage_in]])
{
    float alpha = saturate(in.color.a);
    return float4(in.color.rgb * alpha, alpha);
}

// Screen-space 2D UI overlay, drawn last with depth off. Vertices are
// framebuffer pixels (top-left origin, y down), read by vertex_id. One pipeline
// draws fills and text: fills sample the atlas white texel, glyphs their
// coverage cell. Output is premultiplied for the premultiplied-over blend.

typedef struct
{
    float4 position [[position]];
    float2 uv;
    float4 color;
} UIVertexOut;

vertex UIVertexOut uiVertex(
    uint vertexID [[vertex_id]],
    const device UIVertex *vertices [[buffer(BufferIndexUIVertices)]],
    constant UIFrameUniforms &frame [[buffer(BufferIndexUIUniforms)]])
{
    const device UIVertex &in = vertices[vertexID];
    float2 normalized = in.position / frame.viewportSize;
    UIVertexOut out;
    // Pixel origin top-left, y down -> NDC origin center, y up. z = 0 keeps UI
    // in front; the pass runs depth-test-always with writes off.
    out.position = float4(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0, 0.0, 1.0);
    out.uv = in.uv;
    out.color = in.color;
    return out;
}

fragment float4 uiFragment(
    UIVertexOut in [[stage_in]],
    texture2d<float> atlas [[texture(TextureIndexUIAtlas)]],
    sampler uiSampler [[sampler(SamplerIndexUIAtlas)]])
{
    float coverage = atlas.sample(uiSampler, in.uv).r;
    float alpha = in.color.a * coverage;
    return float4(in.color.rgb * alpha, alpha);
}

// SWF display-list layer, drawn after the 3D scene and before the dev UI.
// Each draw carries its own transform in SWFDrawUniforms. Fills resolve in
// straight alpha, apply the CXFORM, then premultiply for blending. Clip layers
// use the stencil-only swfMaskFragment.

typedef struct
{
    float4 position [[position]];
    float2 uv;
    float2 fillPosition;
} SWFVertexOut;

static inline float2 swfApplyAffine(float4 rotation, float2 translation, float2 p)
{
    return float2(
        rotation.x * p.x + rotation.z * p.y + translation.x,
        rotation.y * p.x + rotation.w * p.y + translation.y);
}

vertex SWFVertexOut swfVertex(
    uint vertexID [[vertex_id]],
    const device SWFVertex *vertices [[buffer(BufferIndexSWFVertices)]],
    constant SWFDrawUniforms &draw [[buffer(BufferIndexSWFUniforms)]])
{
    const device SWFVertex &in = vertices[vertexID];
    float2 clip = swfApplyAffine(draw.transformRotation, draw.transformTranslation, in.position);
    SWFVertexOut out;
    out.position = float4(clip, 0.0, 1.0);
    out.uv = in.uv;
    out.fillPosition = swfApplyAffine(draw.fillRotation, draw.fillTranslation, in.position);
    return out;
}

/// SpreadMode folding of the raw gradient parameter into 0..1 (spec p. 135).
static inline float swfSpread(float t, uint mode)
{
    if (mode == SWFGradientSpreadRepeat) {
        return fract(t);
    }
    if (mode == SWFGradientSpreadReflect) {
        float period = fract(t * 0.5) * 2.0;
        return period <= 1.0 ? period : 2.0 - period;
    }
    return saturate(t);
}

fragment float4 swfFragment(
    SWFVertexOut in [[stage_in]],
    constant SWFDrawUniforms &draw [[buffer(BufferIndexSWFUniforms)]],
    texture2d<float> glyphAtlas [[texture(TextureIndexUIAtlas)]],
    texture2d<float> bitmap [[texture(TextureIndexSWFBitmap)]],
    texture2d<float> gradientRamp [[texture(TextureIndexSWFGradient)]],
    sampler clampSampler [[sampler(SamplerIndexUIAtlas)]],
    sampler repeatSampler [[sampler(SamplerIndexSWFRepeat)]])
{
    float4 straight = draw.baseColor;
    switch (draw.fillMode) {
    case SWFFillModeGlyph:
        straight.a *= glyphAtlas.sample(clampSampler, in.uv).r;
        break;
    case SWFFillModeBitmap: {
        float4 sampled = draw.bitmapTiled != 0 ? bitmap.sample(repeatSampler, in.fillPosition)
                                               : bitmap.sample(clampSampler, in.fillPosition);
        if (draw.sourcePremultiplied != 0 && sampled.a > 0.0) {
            sampled.rgb /= sampled.a;
        }
        straight = sampled;
        break;
    }
    case SWFFillModeLinearGradient:
    case SWFFillModeRadialGradient: {
        // Gradient square: fillPosition is normalized to -1..1; the linear
        // parameter runs left -> right, the radial one out from the center
        // (spec chapter 7, pp. 134-136).
        float raw = draw.fillMode == SWFFillModeLinearGradient ? in.fillPosition.x * 0.5 + 0.5
                                                               : length(in.fillPosition);
        float t = swfSpread(raw, draw.gradientSpread);
        straight = gradientRamp.sample(clampSampler, float2(t, draw.gradientV));
        break;
    }
    default:
        break;
    }
    straight = saturate(straight * draw.colorMultiply + draw.colorAdd);
    return float4(straight.rgb * straight.a, straight.a);
}

/// Stencil-only mask draws: zero premultiplied output leaves the color
/// attachment untouched under the pass's blending, so the mask pipeline needs
/// no color-write-mask special case; only the stencil operation matters.
fragment float4 swfMaskFragment(SWFVertexOut in [[stage_in]])
{
    return float4(0.0);
}

// Image-space composite: one fullscreen triangle over a copy of the scene color.
// Order: blur, double vision, tone mapping, saturation, brightness, contrast, tint, fade
// (docs/rendering/image-space.md). The blur is a cheap two-ring disc.
constant float3 imageSpaceLuminance = float3(0.2126, 0.7152, 0.0722);

static float3 imageSpaceBlur(
    texture2d<float> scene,
    sampler linearClamp,
    float2 uv,
    float2 texel,
    float radius,
    float3 center)
{
    float3 sum = center;
    float count = 1.0;
    for (int ring = 1; ring <= 2; ++ring) {
        float reach = radius * float(ring) * 0.5;
        for (int tap = 0; tap < 6; ++tap) {
            float angle = (float(tap) + 0.5 * float(ring)) * 1.0471976;
            float2 offset = float2(cos(angle), sin(angle)) * reach * texel;
            sum += scene.sample(linearClamp, uv + offset).rgb;
            count += 1.0;
        }
    }
    return sum / count;
}

// HDR tone mapping: every 16th pixel each way adds its fixed-point log2 luminance to
// the slot's counters for the eye (EyeAdaptation.swift), then the exposure scales the
// color and an extended Reinhard curve maps the white point to display white.
static void imageSpaceMeasure(
    float2 position,
    float3 color,
    constant ImageSpaceUniforms &uniforms,
    device atomic_uint *luminance)
{
    uint2 pixel = uint2(position);
    if (uniforms.toneMapping.z < 0.5 || any((pixel & 15u) != 0u)) {
        return;
    }
    float logLuminance = log2(max(dot(color, imageSpaceLuminance), 1.0e-5)) + 16.0;
    uint fixedPoint = uint(clamp(logLuminance, 0.0, 32.0) * 256.0);
    atomic_fetch_add_explicit(&luminance[0], fixedPoint, memory_order_relaxed);
    atomic_fetch_add_explicit(&luminance[1], 1u, memory_order_relaxed);
}

static float3 imageSpaceToneMap(float3 color, constant ImageSpaceUniforms &uniforms)
{
    color *= uniforms.toneMapping.x;
    float white = uniforms.toneMapping.y;
    if (white > 0.0) {
        color = color * (1.0 + color / (white * white)) / (1.0 + color);
    }
    return color;
}

static float4 imageSpaceGrade(float3 color, constant ImageSpaceUniforms &uniforms)
{
    color = imageSpaceToneMap(color, uniforms);
    float luminance = dot(color, imageSpaceLuminance);
    color = mix(float3(luminance), color, uniforms.grading.x);
    color *= uniforms.grading.y;
    float3 encoded = pow(max(color, 0.0), 1.0 / 2.2);
    encoded = (encoded - 0.5) * uniforms.grading.z + 0.5;
    color = pow(max(encoded, 0.0), 2.2);
    float tinted = dot(color, imageSpaceLuminance);
    color = mix(color, tinted * uniforms.tint.rgb, uniforms.tint.a);
    color = mix(color, uniforms.fade.rgb, uniforms.fade.a);
    return float4(saturate(color), 1.0);
}

fragment float4 imageSpaceFragment(
    SkyVertexOut in [[stage_in]],
    constant ImageSpaceUniforms &uniforms [[buffer(BufferIndexImageSpaceUniforms)]],
    device atomic_uint *luminance [[buffer(BufferIndexImageSpaceLuminance)]],
    texture2d<float> scene [[texture(TextureIndexSceneColor)]])
{
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float2 size = float2(scene.get_width(), scene.get_height());
    float2 texel = 1.0 / size;
    float2 uv = in.position.xy * texel;
    float3 color = scene.sample(linearClamp, uv).rgb;
    imageSpaceMeasure(in.position.xy, color, uniforms, luminance);
    if (uniforms.grading.w > 0.5) {
        color = imageSpaceBlur(scene, linearClamp, uv, texel, uniforms.grading.w, color);
    }
    float doubleVision = saturate(uniforms.extra.x);
    if (doubleVision > 0.0) {
        float3 ghost = scene.sample(linearClamp, uv + float2(0.02 * doubleVision, 0.0)).rgb;
        color = mix(color, ghost, 0.5 * doubleVision);
    }
    return imageSpaceGrade(color, uniforms);
}

/// The same grade without the copy: it reads the pixel from tile memory, so it serves
/// frames with no blur and no double vision, which need neighbor pixels.
fragment float4 imageSpaceTileFragment(
    SkyVertexOut in [[stage_in]],
    constant ImageSpaceUniforms &uniforms [[buffer(BufferIndexImageSpaceUniforms)]],
    device atomic_uint *luminance [[buffer(BufferIndexImageSpaceLuminance)]],
    float4 scene [[color(0)]])
{
    imageSpaceMeasure(in.position.xy, scene.rgb, uniforms, luminance);
    return imageSpaceGrade(scene.rgb, uniforms);
}

// Effect-shader membrane: an additive glow over the target's meshes, brighter at
// grazing angles (docs/rendering/visual-effects.md). Blending is one + one.
fragment float4 membraneFragment(
    StaticVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant MembraneUniforms &membrane [[buffer(BufferIndexMembraneUniforms)]])
{
    float3 toEye = normalize(frame.cameraPosition - in.worldPosition);
    float facing = saturate(abs(dot(normalize(in.normal), toEye)));
    float rim = pow(1.0 - facing, max(membrane.edge.a, 0.05));
    return float4(membrane.fill.rgb + membrane.edge.rgb * rim, 0.0);
}
// Asset format comparison: decodes any sampled texture (BC, ASTC, RGBA8) to
// RGBA8, so two formats compare on the pixels the GPU sees. A render pass, not a
// compute pass, because virtual GPUs such as CI runners lack Metal 4 compute.
struct TextureReadbackVertexOut
{
    float4 position [[position]];
};

vertex TextureReadbackVertexOut textureReadbackVertex(uint vertexID [[vertex_id]])
{
    float2 corner = float2((vertexID << 1) & 2, vertexID & 2);
    TextureReadbackVertexOut out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

fragment float4 textureReadbackCopy(
    TextureReadbackVertexOut in [[stage_in]], texture2d<float, access::read> source [[texture(0)]])
{
    return source.read(uint2(in.position.xy));
}

// GPU frustum culling (docs/rendering/gpu-culling.md). The p-vertex test matches
// `Frustum.intersects`, so the CPU and GPU paths keep the same instances.
static bool cullPlaneKeeps(float4 plane, float3 lower, float3 upper)
{
    float3 farthest = select(lower, upper, plane.xyz >= 0.0);
    return !(dot(plane.xyz, farthest) + plane.w < 0.0);
}

kernel void cullInstances(
    device const CullInstance *instances [[buffer(CullBufferIndexInstances)]],
    constant CullParameters &parameters [[buffer(CullBufferIndexParameters)]],
    device InstanceTransform *output [[buffer(CullBufferIndexOutput)]],
    device atomic_uint *arguments [[buffer(CullBufferIndexArguments)]],
    uint index [[thread_position_in_grid]])
{
    if (index >= parameters.instanceCount) {
        return;
    }
    device const CullInstance &instance = instances[index];
    if (instance.boundsMax.w > 0.0) {
        for (uint plane = 0; plane < 6; plane++) {
            if (!cullPlaneKeeps(
                    parameters.planes[plane], instance.boundsMin.xyz, instance.boundsMax.xyz)) {
                return;
            }
        }
    }
    uint countWord = instance.group * CullConstantArgumentWords + 1;
    uint slot = atomic_fetch_add_explicit(&arguments[countWord], 1, memory_order_relaxed);
    output[instance.outputBase + slot] = instance.transform;
}

// Temporal upscaling motion (docs/rendering/upscaling.md). Motion is last frame's
// texture coordinate minus this frame's, both without the jitter.
static float2 textureCoordinate(float4 clip)
{
    return clip.xy / clip.w * float2(0.5, -0.5) + 0.5;
}

static float2 motionBetween(float4 currentClip, float4 previousClip)
{
    return textureCoordinate(previousClip) - textureCoordinate(currentClip);
}

// Every pixel moved only by the camera: reproject its depth with last frame's camera.
fragment float2 cameraMotionFragment(
    TextureReadbackVertexOut in [[stage_in]],
    constant UpscaleMotionUniforms &motion [[buffer(BufferIndexMotionUniforms)]],
    depth2d<float, access::read> depth [[texture(TextureIndexDiffuse)]])
{
    uint2 pixel = uint2(in.position.xy);
    float sceneDepth = depth.read(pixel);
    if (sceneDepth < motion.nearDepthLimit) {
        return float2(0.0);
    }
    float2 size = float2(depth.get_width(), depth.get_height());
    float2 ndc = in.position.xy / size * float2(2.0, -2.0) + float2(-1.0, 1.0);
    float4 world = motion.inverseJitteredViewProjection * float4(ndc, sceneDepth, 1.0);
    world /= world.w;
    return motionBetween(motion.viewProjection * world, motion.previousViewProjection * world);
}

struct MotionVertexOut
{
    float4 position [[position]];
    float4 currentClip;
    float4 previousClip;
};

static MotionVertexOut motionVertex(
    float4 world,
    float4 previousWorld,
    constant FrameUniforms &frame,
    constant UpscaleMotionUniforms &motion)
{
    MotionVertexOut out;
    // The jittered matrix the scene pass used, so the depth test matches its surface.
    out.position = frame.viewProjectionMatrix * world;
    out.currentClip = motion.viewProjection * world;
    out.previousClip = motion.previousViewProjection * previousWorld;
    return out;
}

vertex MotionVertexOut staticMotionVertex(
    StaticVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant UpscaleMotionUniforms &motion [[buffer(BufferIndexMotionUniforms)]],
    const device MotionInstance *instances [[buffer(BufferIndexMotionInstances)]])
{
    const device MotionInstance &instance = instances[instanceID];
    float4 local = float4(in.position, 1.0);
    return motionVertex(instance.current * local, instance.previous * local, frame, motion);
}

vertex MotionVertexOut skinnedMotionVertex(
    SkinnedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant UpscaleMotionUniforms &motion [[buffer(BufferIndexMotionUniforms)]],
    const device MotionInstance *instances [[buffer(BufferIndexMotionInstances)]],
    const device matrix_float4x4 *bones [[buffer(BufferIndexBoneMatrices)]],
    const device matrix_float4x4 *previousBones [[buffer(BufferIndexPreviousBoneMatrices)]])
{
    float4 local = float4(in.position, 1.0);
    float4 skinned = 0.0;
    float4 previousSkinned = 0.0;
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        ushort bone = in.boneIndices[influence];
        skinned += weight * (bones[bone] * local);
        previousSkinned += weight * (previousBones[bone] * local);
    }
    const device MotionInstance &instance = instances[instanceID];
    return motionVertex(
        instance.current * skinned, instance.previous * previousSkinned, frame, motion);
}

fragment float2 objectMotionFragment(MotionVertexOut in [[stage_in]])
{
    return motionBetween(in.currentClip, in.previousClip);
}

// Copies the upscaled frame into the drawable before the menus and the HUD draw.
fragment float4 upscaleCompositeFragment(
    TextureReadbackVertexOut in [[stage_in]],
    texture2d<float, access::read> upscaled [[texture(TextureIndexDiffuse)]])
{
    return float4(upscaled.read(uint2(in.position.xy)).rgb, 1.0);
}
