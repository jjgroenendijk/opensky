// The compute passes that run between the scene copy and the image-space composite:
// ambient occlusion with the game's contrast curve, blend over time, and blur
// (docs/rendering/post-effects.md#ambient-occlusion).

#include "ShaderCommon.h"
#include "PostEffects.h"

// The pixel's occlusion after the contrast curve: A = max(1 - sum x intensity / R^6, 0),
// then A to the contrast exponent.
static inline float occlusionContrast(float sum, constant PostEffectUniforms &post)
{
    float plain = max(1.0 - sum * post.ambientOcclusionCurve.x, 0.0);
    return pow(plain, post.ambientOcclusionCurve.y);
}

// Last frame's occlusion at this world position. The history weight falls linearly as
// the occlusion and the depth differ, as in the game; no hard cut.
static inline float occlusionBlend(
    float current, float3 world, texture2d<float> history, constant PostEffectUniforms &post)
{
    if (post.previousCamera.w < 0.5) {
        return current;
    }
    float4 clip = post.previousViewProjection * float4(world, 1.0);
    if (clip.w <= 0.0) {
        return current;
    }
    float2 uv = float2(clip.x, -clip.y) / clip.w * 0.5 + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0)) {
        return current;
    }
    float2 previous = history.sample(postLinear, uv).rg;
    float expected = distance(world, post.previousCamera.xyz);
    float depthShift = abs(min(previous.g, 7000.0) - min(expected, 7000.0)) / 7000.0;
    float sameDepth = max(1.0 - post.ambientOcclusionCurve.w * depthShift, 0.0);
    float sameValue = saturate(1.0 - post.ambientOcclusionCurve.z * abs(previous.r - current));
    return mix(current, previous.r, sameDepth * sameValue);
}

// Writes the occlusion and the camera distance of each pixel; the sky and snow write 1.
kernel void occlusionTrace(
    uint2 gid [[thread_position_in_grid]],
    constant PostEffectUniforms &post [[buffer(BufferIndexPostEffectUniforms)]],
    depth2d<float> depth [[texture(PostComputeTextureIndexDepth)]],
    texture2d<float> scene [[texture(PostComputeTextureIndexScene)]],
    texture2d<float> history [[texture(PostComputeTextureIndexHistory)]],
    texture2d<float, access::write> output [[texture(PostComputeTextureIndexOutput)]])
{
    uint2 size = uint2(output.get_width(), output.get_height());
    if (any(gid >= size)) {
        return;
    }
    float2 texel = 1.0 / float2(size);
    float2 uv = (float2(gid) + 0.5) * texel;
    float stored = depth.sample(postNearest, uv);
    if (stored >= 1.0) {
        output.write(float4(1.0, 1.0e9, 0.0, 0.0), gid);
        return;
    }
    float3 world = postWorldPosition(uv, stored, post);
    float range = distance(world, post.camera.xyz);
    if (scene.sample(postNearest, uv).a < 0.5) {
        output.write(float4(1.0, range, 0.0, 0.0), gid);
        return;
    }
    PostPixel pixel = {uv, texel, float2(gid) + 0.5, stored, world};
    float3 normal = postSurfaceNormal(pixel, post.camera.xyz, depth, post);
    float sum = postAmbientOcclusionSum(pixel, normal, post.camera.xyz, depth, post);
    float occlusion = occlusionBlend(occlusionContrast(sum, post), world, history, post);
    output.write(float4(occlusion, range, 0.0, 0.0), gid);
}

// The game's 7-tap blur at 0, +-2, +-4, +-6 texels; a tap on another surface counts less.
static inline float
occlusionBlur(uint2 gid, int2 axis, texture2d<float> source, texture2d<float> traced)
{
    constexpr float weights[4] = {0.153, 0.445, 0.423, 0.393};
    int2 last = int2(source.get_width(), source.get_height()) - 1;
    float centre = traced.read(gid).g;
    float sum = source.read(gid).r * weights[0];
    float total = weights[0];
    for (int step = 1; step < 4; ++step) {
        for (int side = -1; side <= 1; side += 2) {
            uint2 tap = uint2(clamp(int2(gid) + axis * (2 * step * side), int2(0), last));
            float gap = abs(traced.read(tap).g - centre) / max(centre * 0.05, 1.0);
            float weight = weights[step] * saturate(1.0 - gap);
            sum += source.read(tap).r * weight;
            total += weight;
        }
    }
    return sum / total;
}

kernel void occlusionBlurHorizontal(
    uint2 gid [[thread_position_in_grid]],
    texture2d<float> traced [[texture(PostComputeTextureIndexHistory)]],
    texture2d<float> source [[texture(PostComputeTextureIndexSource)]],
    texture2d<float, access::write> output [[texture(PostComputeTextureIndexOutput)]])
{
    if (any(gid >= uint2(output.get_width(), output.get_height()))) {
        return;
    }
    output.write(float4(occlusionBlur(gid, int2(1, 0), source, traced)), gid);
}

kernel void occlusionBlurVertical(
    uint2 gid [[thread_position_in_grid]],
    texture2d<float> traced [[texture(PostComputeTextureIndexHistory)]],
    texture2d<float> source [[texture(PostComputeTextureIndexSource)]],
    texture2d<float, access::write> output [[texture(PostComputeTextureIndexOutput)]])
{
    if (any(gid >= uint2(output.get_width(), output.get_height()))) {
        return;
    }
    output.write(float4(occlusionBlur(gid, int2(0, 1), source, traced)), gid);
}
