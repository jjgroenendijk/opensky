#include "ShaderCommon.h"
#include "PostEffects.h"

// Image-space composite: one fullscreen triangle over a copy of the scene color.
// Order: blur, radial blur, motion blur, double vision, the screen-space effects, bloom,
// tone mapping, saturation, brightness, contrast, tint, fade
// (docs/rendering/image-space.md). The blur is a cheap two-ring disc.
constant float3 imageSpaceLuminance = float3(0.2125, 0.7154, 0.0721);

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

// Radial blur: taps on the line to the centre, weighted by the ramps of the CK wiki's
// "ImageSpace Modifiers" page. The radius is a share of the centre-to-corner distance.
static float3 imageSpaceRadialBlur(
    texture2d<float> scene,
    sampler linearClamp,
    float2 uv,
    float3 color,
    constant ImageSpaceUniforms &uniforms)
{
    float4 shape = uniforms.radialBlur;
    if (shape.x <= 0.0) {
        return color;
    }
    float2 offset = uv - uniforms.extra.zw;
    float radius = length(offset) * 1.4142136;
    float weight = saturate((radius - shape.z) * shape.y);
    float downStart = uniforms.radialBlurEnd.x;
    if (downStart > shape.z) {
        weight *= saturate(1.0 - (radius - downStart) * shape.w);
    }
    if (weight <= 0.0) {
        return color;
    }
    float reach = shape.x * 0.01 * weight;
    float3 sum = color;
    for (int tap = 1; tap < 8; ++tap) {
        sum += scene.sample(linearClamp, uv - offset * reach * float(tap) / 7.0).rgb;
    }
    return sum / 8.0;
}

// Motion blur: the camera's turn since last frame, from the pixel's far-plane direction.
// The trail is that of a frame blend that keeps `strength` of the last frame.
static float3 imageSpaceMotionBlur(
    texture2d<float> scene,
    sampler linearClamp,
    float2 uv,
    float3 color,
    constant ImageSpaceUniforms &uniforms)
{
    float strength = saturate(uniforms.extra.y);
    if (strength <= 0.0) {
        return color;
    }
    float4 previous = uniforms.reprojection * float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 1.0, 1.0);
    if (previous.w <= 1.0e-5) {
        return color;
    }
    float2 before = float2(previous.x, -previous.y) / previous.w * 0.5 + 0.5;
    float2 trail = (before - uv) * (3.0 * strength / max(1.0 - strength, 0.05));
    float span = length(trail);
    if (span > 0.1) {
        trail *= 0.1 / span;
    }
    float3 sum = color;
    for (int tap = 1; tap < 8; ++tap) {
        sum += scene.sample(linearClamp, uv + trail * float(tap) / 7.0).rgb;
    }
    return sum / 8.0;
}

// Bloom: three rings of eight taps over the bloom radius. Each tap adds what it holds
// above the threshold, times the scale. Only an HDR target has colour above 1 to spread.
static float3 imageSpaceBloom(
    texture2d<float> scene,
    sampler linearClamp,
    float2 uv,
    float2 texel,
    float3 color,
    constant ImageSpaceUniforms &uniforms)
{
    float4 bloom = uniforms.bloom;
    if (bloom.z <= 0.0 || bloom.x <= 0.0) {
        return color;
    }
    float3 glow = max(color - bloom.y, 0.0);
    float total = 1.0;
    for (int ring = 1; ring <= 3; ++ring) {
        float reach = bloom.x * float(ring) / 3.0;
        float weight = 1.0 / float(ring);
        for (int tap = 0; tap < 8; ++tap) {
            float angle = (float(tap) + 0.5 * float(ring)) * 0.7853982;
            float2 offset = float2(cos(angle), sin(angle)) * reach * texel;
            glow += max(scene.sample(linearClamp, uv + offset).rgb - bloom.y, 0.0) * weight;
            total += weight;
        }
    }
    return color + glow / total * bloom.z;
}

// Eye adaptation input: every 16th pixel each way adds its fixed-point luminance, in the
// game's colour values, to the counters of its screen quarter (EyeAdaptation.swift). A plain
// mean per quarter, as the game's down-sample chain to 2 x 2 gives.
static void imageSpaceMeasure(
    float2 position,
    float2 uv,
    float3 color,
    constant ImageSpaceUniforms &uniforms,
    device atomic_uint *luminance)
{
    uint2 pixel = uint2(position);
    if (uniforms.toneMapping.z < 0.5 || any((pixel & 15u) != 0u)) {
        return;
    }
    uint quarter = (uv.y >= 0.5 ? 2u : 0u) + (uv.x >= 0.5 ? 1u : 0u);
    float value = clamp(dot(toGamma(color), imageSpaceLuminance), 0.0, 64.0);
    atomic_fetch_add_explicit(&luminance[quarter * 2u], uint(value * 1024.0), memory_order_relaxed);
    atomic_fetch_add_explicit(&luminance[quarter * 2u + 1u], 1u, memory_order_relaxed);
}

// One value per screen quarter, blended as a linear sampler reads a 2 x 2 texture.
static float imageSpaceQuarterValue(float4 quarters, float2 uv)
{
    float2 blend = saturate(uv * 2.0 - 0.5);
    return mix(mix(quarters.x, quarters.y, blend.x), mix(quarters.z, quarters.w, blend.x), blend.y);
}

// The game tone maps and grades its stored colour values, which are gamma values here, so
// the pass works on toGamma of the scene and returns it linear (docs/rendering/image-space.md).
static float4 imageSpaceGrade(float3 color, float2 uv, constant ImageSpaceUniforms &uniforms)
{
    float3 scene = toGamma(color);
    if (uniforms.toneMapping.z > 1.5 && uniforms.toneMapping.y > 0.0) {
        float lum = max(dot(scene, imageSpaceLuminance), 1.0e-5);
        float x = lum * imageSpaceQuarterValue(uniforms.quarterExposure, uv);
        float white = uniforms.toneMapping.y * 1.1;
        float mapped = x * (1.0 + x / (white * white)) / (1.0 + x);
        scene *= mapped / lum;
    }
    float grey = dot(scene, imageSpaceLuminance);
    scene = mix(float3(grey), scene, uniforms.grading.x);
    scene = mix(scene, grey * uniforms.tint.rgb, uniforms.tint.a);
    float pivot = imageSpaceQuarterValue(uniforms.quarterPivot, uv);
    scene = uniforms.grading.z * (uniforms.grading.y * scene - pivot) + pivot;
    scene = mix(saturate(scene), uniforms.fade.rgb, uniforms.fade.a);
    return float4(toLinear(scene), 1.0);
}

fragment float4 imageSpaceFragment(
    SkyVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant ImageSpaceUniforms &uniforms [[buffer(BufferIndexImageSpaceUniforms)]],
    constant PostEffectUniforms &post [[buffer(BufferIndexPostEffectUniforms)]],
    device atomic_uint *luminance [[buffer(BufferIndexImageSpaceLuminance)]],
    texture2d<float> scene [[texture(TextureIndexSceneColor)]],
    depth2d<float> sceneDepth [[texture(TextureIndexSceneDepth)]],
    texture2d<float> occlusionMap [[texture(TextureIndexPostOcclusion)]],
    texture2d<float> indirectMap [[texture(TextureIndexPostIndirectLight)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    sampler shadowCompare [[sampler(SamplerIndexShadowCompare)]])
{
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float2 size = float2(scene.get_width(), scene.get_height());
    float2 texel = 1.0 / size;
    float2 uv = in.position.xy * texel;
    float3 color = (post.effects & PostEffectFlagAntiAliasing) != 0
                       ? postFXAA(scene, uv, texel)
                       : scene.sample(linearClamp, uv).rgb;
    if (uniforms.grading.w > 0.5) {
        color = imageSpaceBlur(scene, linearClamp, uv, texel, uniforms.grading.w, color);
    }
    color = imageSpaceRadialBlur(scene, linearClamp, uv, color, uniforms);
    color = imageSpaceMotionBlur(scene, linearClamp, uv, color, uniforms);
    float doubleVision = saturate(uniforms.extra.x);
    if (doubleVision > 0.0) {
        float3 ghost = scene.sample(linearClamp, uv + float2(0.02 * doubleVision, 0.0)).rgb;
        color = mix(color, ghost, 0.5 * doubleVision);
    }
    if (post.effects != 0) {
        float depth = sceneDepth.sample(postNearest, uv);
        PostPixel pixel = {uv, texel, in.position.xy, depth, postWorldPosition(uv, depth, post)};
        color = postApply(
            color, pixel, frame, post, scene, sceneDepth, {occlusionMap, indirectMap}, shadowMap,
            shadowCompare);
    }
    // The game measures the frame after the volumetric light, so the adapted luminance,
    // which is also the contrast pivot, includes it.
    imageSpaceMeasure(in.position.xy, uv, color, uniforms, luminance);
    color = imageSpaceBloom(scene, linearClamp, uv, texel, color, uniforms);
    return imageSpaceGrade(color, uv, uniforms);
}

/// The same grade without the copy: it reads the pixel from tile memory, so it serves
/// frames with no blur, double vision, or bloom, which need neighbor pixels.
fragment float4 imageSpaceTileFragment(
    SkyVertexOut in [[stage_in]],
    constant ImageSpaceUniforms &uniforms [[buffer(BufferIndexImageSpaceUniforms)]],
    device atomic_uint *luminance [[buffer(BufferIndexImageSpaceLuminance)]],
    float4 scene [[color(0)]])
{
    // The triangle's uv has y up; the quarters count from the top of the screen.
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    imageSpaceMeasure(in.position.xy, uv, scene.rgb, uniforms, luminance);
    return imageSpaceGrade(scene.rgb, uv, uniforms);
}

// Asset format comparison: decodes any sampled texture (BC, ASTC, RGBA8) to
// RGBA8, so two formats compare on the pixels the GPU sees. A render pass, not a
// compute pass, because virtual GPUs such as CI runners lack Metal 4 compute.
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

// Copies the upscaled frame into the drawable before the menus and the HUD draw.
fragment float4 upscaleCompositeFragment(
    TextureReadbackVertexOut in [[stage_in]],
    texture2d<float, access::read> upscaled [[texture(TextureIndexDiffuse)]])
{
    return float4(upscaled.read(uint2(in.position.xy)).rgb, 1.0);
}
