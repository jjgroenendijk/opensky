// Screen-space effects of the image-space composite (docs/rendering/post-effects.md).
// Each one reads the scene colour copy and the scene depth copy of the split pass.

#ifndef PostEffects_h
#define PostEffects_h

#include "ShaderCommon.h"

constexpr sampler postNearest(filter::nearest, address::clamp_to_edge);
constexpr sampler postLinear(filter::linear, address::clamp_to_edge);

// A pixel's world position, rebuilt from its stored depth.
static inline float3 postWorldPosition(float2 uv, float depth, constant PostEffectUniforms &post)
{
    float4 clip = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    float4 world = post.inverseViewProjection * clip;
    return world.xyz / world.w;
}

static inline float3 postWorldAt(float2 uv, depth2d<float> depth, constant PostEffectUniforms &post)
{
    return postWorldPosition(uv, depth.sample(postNearest, uv), post);
}

// Interleaved gradient noise: a value from 0 to 1 per pixel. It turns banding into grain.
static inline float postNoise(float2 pixel)
{
    return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
}

// The shorter of the two steps to the neighbours, so an edge does not bend the normal.
static inline float3 postNeighbourStep(float3 world, float3 ahead, float3 behind)
{
    float3 forward = ahead - world;
    float3 back = world - behind;
    return dot(forward, forward) < dot(back, back) ? forward : back;
}

typedef struct
{
    float2 uv;
    float2 texel;
    float2 pixel;
    float depth;
    float3 world;
} PostPixel;

// Ambient occlusion: twelve depth taps on a spiral around the pixel. A tap above the
// surface plane and inside the radius darkens the pixel, more when it is near.
static inline float postAmbientOcclusion(
    PostPixel pixel, float3 camera, depth2d<float> depth, constant PostEffectUniforms &post)
{
    float3 normal = normalize(cross(
        postNeighbourStep(pixel.world, postWorldAt(pixel.uv + float2(pixel.texel.x, 0), depth, post),
                          postWorldAt(pixel.uv - float2(pixel.texel.x, 0), depth, post)),
        postNeighbourStep(pixel.world, postWorldAt(pixel.uv + float2(0, pixel.texel.y), depth, post),
                          postWorldAt(pixel.uv - float2(0, pixel.texel.y), depth, post))));
    if (dot(normal, camera - pixel.world) < 0.0) {
        normal = -normal;
    }
    float radius = post.ambientOcclusion.x;
    float2 reach = radius * post.projection.xy * 0.5 / max(distance(pixel.world, camera), 1.0);
    reach = min(reach, float2(0.1));
    float turn = postNoise(pixel.pixel) * 6.2831853;
    float sum = 0.0;
    for (int tap = 0; tap < 12; ++tap) {
        float share = (float(tap) + 0.5) / 12.0;
        float angle = turn + float(tap) * 2.3999632;
        float2 tapUV = pixel.uv + float2(cos(angle), sin(angle)) * reach * share;
        float3 toTap = postWorldAt(tapUV, depth, post) - pixel.world;
        float distanceSquared = dot(toTap, toTap);
        float falloff = saturate(1.0 - distanceSquared / (radius * radius));
        float rise = dot(toTap * rsqrt(max(distanceSquared, 1.0e-4)), normal);
        sum += max(rise - post.ambientOcclusion.z, 0.0) * falloff;
    }
    return saturate(1.0 - post.ambientOcclusion.y * sum / 12.0);
}

// One cascade tap per march step; the march takes many steps, so each takes one tap.
static inline float postSunLit(
    float3 world, constant FrameUniforms &frame, depth2d_array<float> shadowMap, sampler compare)
{
    int cascade = sunShadowCascadeIndex(world, frame);
    if (cascade < 0) {
        return 1.0;
    }
    float4 clip = frame.shadowViewProjections[cascade] * float4(world, 1.0);
    float3 ndc = clip.xyz / clip.w;
    if (any(abs(ndc.xy) > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
        return 1.0;
    }
    float2 uv = ndc.xy * float2(0.5, -0.5) + 0.5;
    return shadowMap.sample_compare(compare, uv, cascade, ndc.z - shadowReceiverBias);
}

// Volumetric light: the ray from the camera to the pixel steps through the sun cascades.
// The share of lit steps, a forward-scattering phase, and the ray length set how much
// sun light the air adds.
static inline float3 postVolumetricLight(
    PostPixel pixel,
    bool sky,
    constant FrameUniforms &frame,
    constant PostEffectUniforms &post,
    depth2d_array<float> shadowMap,
    sampler compare)
{
    if (frame.shadowsEnabled == 0) {
        return 0.0;
    }
    float3 toPixel = (sky ? postWorldPosition(pixel.uv, 0.5, post) : pixel.world)
        - frame.cameraPosition;
    float maximum = post.volumetricLight.z;
    float reach = sky ? maximum : min(length(toPixel), maximum);
    float3 direction = normalize(toPixel);
    int steps = max(int(post.volumetricLight.y), 1);
    float offset = postNoise(pixel.pixel);
    float lit = 0.0;
    for (int step = 0; step < steps; ++step) {
        float along = (float(step) + offset) / float(steps) * reach;
        lit += postSunLit(frame.cameraPosition + direction * along, frame, shadowMap, compare);
    }
    lit /= float(steps);
    float asymmetry = post.volumetricLight.w;
    float cosine = dot(direction, -frame.sunDirection);
    float phase = (1.0 - asymmetry * asymmetry)
        / pow(1.0 + asymmetry * asymmetry - 2.0 * asymmetry * cosine, 1.5);
    float scatter = 1.0 - exp(-reach / maximum);
    return frame.sunColor * (lit * phase * scatter * post.volumetricLight.x);
}

// Depth of field: past the focus distance the blur grows over the range, up to the
// strength. Two rings of eight taps; a tap nearer than the focus distance is skipped,
// so a sharp foreground does not bleed into the blur behind it.
static inline float3 postDepthOfField(
    float3 color,
    PostPixel pixel,
    bool sky,
    float3 camera,
    texture2d<float> scene,
    depth2d<float> depth,
    constant PostEffectUniforms &post)
{
    float4 field = post.depthOfField;
    float far = sky ? 1.0 : saturate((distance(pixel.world, camera) - field.y) / max(field.z, 1.0));
    float amount = saturate(field.x) * far;
    if (amount <= 0.0) {
        return color;
    }
    float3 sum = color;
    float weight = 1.0;
    for (int ring = 1; ring <= 2; ++ring) {
        float reach = field.w * amount * float(ring) * 0.5;
        for (int tap = 0; tap < 8; ++tap) {
            float angle = (float(tap) + 0.5 * float(ring)) * 0.7853982;
            float2 tapUV = pixel.uv + float2(cos(angle), sin(angle)) * reach * pixel.texel;
            float tapDepth = depth.sample(postNearest, tapUV);
            if (tapDepth < 1.0
                && distance(postWorldPosition(tapUV, tapDepth, post), camera) < field.y) {
                continue;
            }
            sum += scene.sample(postLinear, tapUV).rgb;
            weight += 1.0;
        }
    }
    return sum / weight;
}

// Every effect the frame turned on, in order, over the colour of one pixel.
static inline float3 postApply(
    float3 color,
    PostPixel pixel,
    constant FrameUniforms &frame,
    constant PostEffectUniforms &post,
    texture2d<float> scene,
    depth2d<float> depth,
    depth2d_array<float> shadowMap,
    sampler compare)
{
    bool sky = pixel.depth >= 1.0;
    if ((post.effects & PostEffectFlagDepthOfField) != 0) {
        color = postDepthOfField(color, pixel, sky, frame.cameraPosition, scene, depth, post);
    }
    if ((post.effects & PostEffectFlagAmbientOcclusion) != 0 && !sky) {
        color *= postAmbientOcclusion(pixel, frame.cameraPosition, depth, post);
    }
    if ((post.effects & PostEffectFlagVolumetricLight) != 0) {
        color += postVolumetricLight(pixel, sky, frame, post, shadowMap, compare);
    }
    return color;
}

#endif /* PostEffects_h */
