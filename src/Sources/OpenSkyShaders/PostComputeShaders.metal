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

// The game's indirect light tap: how much the two surfaces face each other, less a bias,
// over |v|^4, times (R^2 - |v|^2)^3 and a linear falloff to the radius. The tap normal is
// turned around: the game's comes out as noise, and a clean one would reject every facing tap.
static inline float
indirectTapWeight(float3 toTap, float3 normal, float3 tapNormal, float bias, float radius)
{
    float squared = dot(toTap, toTap);
    float facing = dot(toTap, normal) * dot(-toTap, tapNormal);
    float inside = max(radius * radius - squared, 0.0);
    float falloff = 1.0 - saturate(sqrt(squared) / radius);
    return max((facing - bias) / (squared * squared + 0.01), 0.0) * inside * inside * inside *
           falloff;
}

// Last frame's indirect light at this world position. The game's weight: 0.3 times how
// alike the depth is, times the sum over the channels of how alike each is; 0 near the
// screen edge.
static inline float3 indirectBlend(
    float3 current,
    float3 world,
    float depthShare,
    texture2d<float> history,
    constant PostEffectUniforms &post)
{
    if (post.indirectLight.w < 0.5) {
        return current;
    }
    float4 clip = post.previousViewProjection * float4(world, 1.0);
    float2 uv = float2(clip.x, -clip.y) / max(clip.w, 1.0e-4) * 0.5 + 0.5;
    if (clip.w <= 0.0 || any(uv < 0.01) || any(uv > 0.99)) {
        return current;
    }
    float4 previous = history.sample(postLinear, uv);
    float sameDepth = max(1.0 - 200.0 * abs(depthShare - previous.a), 0.0);
    float3 alike = max(1.0 - 0.7 * abs(previous.rgb - current), 0.0);
    float weight = 0.3 * sameDepth * (alike.r + alike.g + alike.b);
    return mix(current, previous.rgb, weight);
}

// The game's per-pixel turn of the taps: an integer hash of the pixel, read as radians.
static inline float indirectPixelTurn(uint2 pixel)
{
    uint hash = (3u * pixel.x) ^ ((pixel.x + 1u) * pixel.y);
    return fmod(float(hash) * 10.0, 6.2831853);
}

// A new turn from 0 to pi each frame, from the frame counter.
static inline float indirectFrameTurn(float frame)
{
    uint state = uint(frame) * 747796405u + 2891336453u;
    state = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    state = (state >> 22u) ^ state;
    return float(state) * (3.14159265 / 4294967296.0);
}

// One bounce of colour from nearby surfaces: 15 taps on a spiral `100 R / z` pixels wide,
// blended with last frame, then faded out by 10,000 units. Writes the light and the view
// depth over 7,000, capped at 1, which the history compares.
kernel void indirectLightTrace(
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
        output.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        return;
    }
    PostPixel pixel = {uv, texel, float2(gid) + 0.5, stored, postWorldPosition(uv, stored, post)};
    float3 camera = post.camera.xyz;
    float3 forward = normalize(postWorldPosition(float2(0.5), 0.5, post) - camera);
    float viewDepth = max(dot(pixel.world - camera, forward), 1.0);
    float depthShare = min(viewDepth / 7000.0, 1.0);
    // The fade is 0 from 10000 units on, so such a pixel traces nothing.
    if (viewDepth >= 10000.0) {
        output.write(float4(0.0, 0.0, 0.0, depthShare), gid);
        return;
    }
    float3 normal = postSurfaceNormal(pixel, camera, depth, post);
    float radius = post.indirectLight.x;
    float2 ndc = uv * 2.0 - 1.0;
    float bias = post.indirectLight.z + 5.0 * dot(ndc, ndc) + 10.0 * max(depthShare - 0.3, 0.0);
    float spread = 100.0 * radius / viewDepth;
    float turn = indirectPixelTurn(gid);
    if (viewDepth <= 3500.0) {
        turn += indirectFrameTurn(post.camera.w);
    }
    float3 sum = 0.0;
    for (int tap = 0; tap < 15; ++tap) {
        float angle = turn + (float(tap) + 0.5) * 3.349334;
        float2 offset = float2(cos(angle), sin(angle)) * spread * ((float(tap) + 0.5) / 15.0);
        // The game rebuilds a tap from the pixel it lands in.
        float2 tapPixelCentre = float2(gid) + trunc(offset) + 0.5;
        float2 tapUV = tapPixelCentre * texel;
        if (any(tapUV < 0.0) || any(tapUV > 1.0)) {
            continue;
        }
        float tapStored = depth.sample(postNearest, tapUV);
        if (tapStored >= 1.0) {
            continue;
        }
        PostPixel tapPixel = {
            tapUV, texel, tapPixelCentre, tapStored, postWorldPosition(tapUV, tapStored, post)};
        // The weight is 0 past the radius, and where |v . N| |v| cannot pass the bias
        // whatever the tap normal is. Such a tap needs no normal and no colour.
        float3 toTap = tapPixel.world - pixel.world;
        float squared = dot(toTap, toTap);
        if (squared >= radius * radius || abs(dot(toTap, normal)) * sqrt(squared) <= bias) {
            continue;
        }
        float3 tapNormal = postSurfaceNormal(tapPixel, camera, depth, post);
        float weight = indirectTapWeight(toTap, normal, tapNormal, bias, radius);
        sum += weight * scene.sample(postLinear, tapUV).rgb;
    }
    float radiusCubed = radius * radius * radius;
    float3 light = max(sum / (radiusCubed * radiusCubed) * post.indirectLight.y / 3.0, 0.0);
    light = indirectBlend(light, pixel.world, depthShare, history, post);
    light *= smoothstep(0.0, 1.0, saturate((10000.0 - viewDepth) / 10000.0));
    output.write(float4(light, depthShare), gid);
}

// The engine's plain separable blur: 15 taps one pixel apart, with no depth test. The
// weights are a Gaussian of deviation 7 / 3, which the game's table is not known to be.
static inline float4 indirectBlur(uint2 gid, int2 axis, texture2d<float> source)
{
    constexpr float weights[8] = {0.1712, 0.1562, 0.1186, 0.0749, 0.0394, 0.0172, 0.0063, 0.0019};
    int2 last = int2(source.get_width(), source.get_height()) - 1;
    float4 sum = source.read(gid) * weights[0];
    for (int step = 1; step < 8; ++step) {
        for (int side = -1; side <= 1; side += 2) {
            uint2 tap = uint2(clamp(int2(gid) + axis * (step * side), int2(0), last));
            sum += source.read(tap) * weights[step];
        }
    }
    return sum;
}

kernel void indirectBlurHorizontal(
    uint2 gid [[thread_position_in_grid]],
    texture2d<float> source [[texture(PostComputeTextureIndexSource)]],
    texture2d<float, access::write> output [[texture(PostComputeTextureIndexOutput)]])
{
    if (any(gid >= uint2(output.get_width(), output.get_height()))) {
        return;
    }
    output.write(indirectBlur(gid, int2(1, 0), source), gid);
}

kernel void indirectBlurVertical(
    uint2 gid [[thread_position_in_grid]],
    texture2d<float> source [[texture(PostComputeTextureIndexSource)]],
    texture2d<float, access::write> output [[texture(PostComputeTextureIndexOutput)]])
{
    if (any(gid >= uint2(output.get_width(), output.get_height()))) {
        return;
    }
    output.write(indirectBlur(gid, int2(0, 1), source), gid);
}
