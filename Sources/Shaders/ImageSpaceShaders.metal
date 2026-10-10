#include "ShaderCommon.h"

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
