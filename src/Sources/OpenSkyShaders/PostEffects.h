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

// Perceptual brightness: the square root of linear luminance.
static inline float postLuma(float3 color)
{
    return sqrt(max(dot(color, float3(0.2126, 0.7152, 0.0722)), 0.0));
}

// FXAA (fast approximate anti-aliasing): where the four diagonal neighbours differ in
// brightness, find the edge direction from them and average along it.
static inline float3 postFXAA(texture2d<float> scene, float2 uv, float2 texel)
{
    float3 middle = scene.sample(postLinear, uv).rgb;
    float northWest = postLuma(scene.sample(postLinear, uv + float2(-1, -1) * texel).rgb);
    float northEast = postLuma(scene.sample(postLinear, uv + float2(1, -1) * texel).rgb);
    float southWest = postLuma(scene.sample(postLinear, uv + float2(-1, 1) * texel).rgb);
    float southEast = postLuma(scene.sample(postLinear, uv + float2(1, 1) * texel).rgb);
    float centre = postLuma(middle);
    float lowest = min(centre, min(min(northWest, northEast), min(southWest, southEast)));
    float highest = max(centre, max(max(northWest, northEast), max(southWest, southEast)));
    if (highest - lowest < max(0.0312, highest * 0.125)) {
        return middle;
    }
    float2 direction = float2(
        (southWest + southEast) - (northWest + northEast),
        (northWest + southWest) - (northEast + southEast));
    float reduce = max((northWest + northEast + southWest + southEast) * 0.03125, 1.0 / 128.0);
    float scale = 1.0 / (min(abs(direction.x), abs(direction.y)) + reduce);
    direction = clamp(direction * scale, -8.0, 8.0) * texel;
    float3 near = 0.5 * (scene.sample(postLinear, uv - direction / 6.0).rgb +
                         scene.sample(postLinear, uv + direction / 6.0).rgb);
    float3 wide = near * 0.5 + 0.25 * (scene.sample(postLinear, uv - direction * 0.5).rgb +
                                       scene.sample(postLinear, uv + direction * 0.5).rgb);
    float wideLuma = postLuma(wide);
    return (wideLuma < lowest || wideLuma > highest) ? near : wide;
}

typedef struct
{
    float2 uv;
    float2 texel;
    float2 pixel;
    float depth;
    float3 world;
} PostPixel;

// The surface normal from the depth of the four neighbours, turned to face the camera.
static inline float3 postSurfaceNormal(
    PostPixel pixel, float3 camera, depth2d<float> depth, constant PostEffectUniforms &post)
{
    float3 normal = normalize(cross(
        postNeighbourStep(
            pixel.world, postWorldAt(pixel.uv + float2(pixel.texel.x, 0), depth, post),
            postWorldAt(pixel.uv - float2(pixel.texel.x, 0), depth, post)),
        postNeighbourStep(
            pixel.world, postWorldAt(pixel.uv + float2(0, pixel.texel.y), depth, post),
            postWorldAt(pixel.uv - float2(0, pixel.texel.y), depth, post))));
    return dot(normal, camera - pixel.world) < 0.0 ? -normal : normal;
}

// The faded sum of the game's 5 tap terms: (R^2 - |v|^2)^3 x (v.N - bias) / (|v|^2 + 0.01).
// The bias grows toward the screen edge and with depth, as in the game.
static inline float postAmbientOcclusionSum(
    PostPixel pixel,
    float3 normal,
    float3 camera,
    depth2d<float> depth,
    constant PostEffectUniforms &post)
{
    float range = distance(pixel.world, camera);
    float fade = 1.0 - smoothstep(0.5, 1.0, range / max(post.ambientOcclusion.w, 1.0));
    if (fade <= 0.0) {
        return 0.0;
    }
    float radius = post.ambientOcclusion.x;
    float radiusSquared = radius * radius;
    float2 ndc = pixel.uv * 2.0 - 1.0;
    float bias =
        post.ambientOcclusion.z + 2.0 * dot(ndc, ndc) + 10.0 * max(range / 7000.0 - 0.3, 0.0);
    float2 reach = radius * post.projection.xy * 0.5 / max(range, 1.0);
    reach = min(reach, float2(0.1));
    float turn = (postNoise(pixel.pixel) + post.camera.w * 0.618034) * 6.2831853;
    float sum = 0.0;
    for (int tap = 0; tap < 5; ++tap) {
        float share = (float(tap) + 0.5) / 5.0;
        float angle = turn + (float(tap) + 0.5) * 2.512;
        float2 tapUV = pixel.uv + float2(cos(angle), sin(angle)) * reach * share;
        float3 toTap = postWorldAt(tapUV, depth, post) - pixel.world;
        float distanceSquared = dot(toTap, toTap);
        float inside = max(radiusSquared - distanceSquared, 0.0);
        float rise = max((dot(toTap, normal) - bias) / (distanceSquared + 0.01), 0.0);
        sum += inside * inside * inside * rise;
    }
    return fade * sum;
}

// Occlusion darkens the lit colour before the fog is added, as the game's fog variant
// does, so fog in front of a crease stays as bright as elsewhere.
static inline float3
postOccludeUnderFog(float3 color, float occlusion, float3 world, constant FrameUniforms &frame)
{
    float2 fog = fogAt(world, frame);
    float3 fogPart = mix(frame.fogNearColor, frame.fogFarColor, fog.y) * fog.y;
    return toLinear(fogPart + max(toGamma(color) - fogPart, 0.0) * occlusion);
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

// Value noise from 0 to 1 over a lattice of unit cells, smooth between the corners.
static inline float postHash(float3 cell)
{
    return fract(sin(dot(cell, float3(127.1, 311.7, 74.7))) * 43758.5453);
}

static inline float postValueNoise(float3 position)
{
    float3 cell = floor(position);
    float3 t = position - cell;
    t = t * t * (3.0 - 2.0 * t);
    float bottom =
        mix(mix(postHash(cell), postHash(cell + float3(1, 0, 0)), t.x),
            mix(postHash(cell + float3(0, 1, 0)), postHash(cell + float3(1, 1, 0)), t.x), t.y);
    float top =
        mix(mix(postHash(cell + float3(0, 0, 1)), postHash(cell + float3(1, 0, 1)), t.x),
            mix(postHash(cell + float3(0, 1, 1)), postHash(cell + float3(1, 1, 1)), t.x), t.y);
    return mix(bottom, top, t.z);
}

// VOLI density: 1 where the noise is full, thinner by up to the density share elsewhere.
// The noise fades to a quarter over 150 units above the camera.
static inline float
postAirDensity(float3 world, float3 camera, float time, constant PostEffectUniforms &post)
{
    float4 density = post.volumetricDensity;
    if (density.x <= 0.0) {
        return 1.0;
    }
    float3 moved = world - float3(density.z, 0.0, -density.w) * time;
    float noise = postValueNoise(moved / max(density.y, 1.0));
    float fall = 1.0 - 0.75 * smoothstep(0.0, 1.0, saturate((world.z - camera.z) / 150.0));
    return 1.0 + density.x * (noise * fall - 1.0);
}

// Volumetric light, as the game adds it (docs/rendering/post-effects.md#volumetric-light):
// the air in front of the pixel is cut into slices that are even in `depth ^ range`. Each
// slice adds its sun-lit share times its density and the phase. The sum times the intensity
// is added to the game's colour values, which the scene pass clamped to 1.
static inline float3 postVolumetricLight(
    float3 color,
    PostPixel pixel,
    bool sky,
    constant FrameUniforms &frame,
    constant PostEffectUniforms &post,
    depth2d_array<float> shadowMap,
    sampler compare)
{
    float3 toPixel =
        (sky ? postWorldPosition(pixel.uv, 0.5, post) : pixel.world) - frame.cameraPosition;
    float range = length(toPixel);
    float3 direction = toPixel / max(range, 1.0e-4);
    float near = post.volumetricPhase.y;
    float exponent = max(post.volumetricLight.z, 1.0);
    // The share of all slices that lie in front of the pixel.
    float front = sky ? 1.0 : pow(saturate(1.0 - near / max(range, near)), exponent);
    int steps = max(int(post.volumetricLight.y), 1);
    float offset = postNoise(pixel.pixel);
    float sum = 0.0;
    for (int step = 0; step < steps; ++step) {
        float slice = (float(step) + offset) / float(steps) * front;
        // The distance of a slice; past the sun cascades the air counts as lit.
        float along = near / max(1.0 - pow(slice, 1.0 / exponent), 1.0e-5);
        float3 point = frame.cameraPosition + direction * min(along, 60000.0);
        float lit = frame.shadowsEnabled == 0 ? 1.0 : postSunLit(point, frame, shadowMap, compare);
        sum += lit * postAirDensity(point, frame.cameraPosition, frame.animationTime, post);
    }
    float asymmetry = post.volumetricLight.w;
    float cosine = dot(direction, -frame.sunDirection);
    float forward =
        (1.0 - asymmetry * asymmetry) / (12.566371 * max(1.0 - asymmetry * cosine, 1.0e-3));
    float phase = 1.0 + post.volumetricPhase.x * (forward - 1.0);
    float amount = post.volumetricLight.x * front * phase * sum / float(steps);
    float3 light = frame.sunColor * post.volumetricColour.w + post.volumetricColour.rgb;
    return toLinear(min(toGamma(color), 1.0) + light * max(amount, 0.0));
}

// Where the depth of field is sharp, how far past it the blur grows, and how strong it is.
struct PostFocus
{
    float clear;
    float span;
    float strength;
    uint sides;
    bool farFirst;
};

// The game's "Use Target" focus: the depth at the view centre, mixed with a ring around it
// by the centre weight; the sky and far taps count as 50,000 units.
static inline float
postCentreFocus(float3 camera, depth2d<float> depth, constant PostEffectUniforms &post)
{
    float centreWeight = post.depthOfFieldMode.w * 8.0;
    float sum = 0.0;
    float weights = 0.0;
    for (int tap = 0; tap < 9; ++tap) {
        float angle = float(tap) * 0.7853982;
        float2 uv = tap == 8 ? float2(0.5) : 0.5 + float2(cos(angle), sin(angle)) * 0.05;
        float stored = depth.sample(postNearest, uv);
        float range = stored >= 1.0
                          ? 50000.0
                          : min(distance(postWorldPosition(uv, stored, post), camera), 50000.0);
        float weight = tap == 8 ? centreWeight : 1.0;
        sum += range * weight;
        weights += weight;
    }
    return sum / weights;
}

// A modifier's values, or with "Use Target" the game's ramps: past a 100-unit focus the
// range grows from 100 to 10,000 and the strength falls from 0.8 to 0.56 by 1,000 units.
static inline PostFocus
postFocusPlane(float3 camera, depth2d<float> depth, constant PostEffectUniforms &post)
{
    uint sides = uint(post.depthOfFieldMode.y);
    if (post.depthOfFieldMode.z < 0.5) {
        float clear = post.depthOfField.y;
        float full = post.depthOfField.z;
        return {
            clear, max(abs(full - clear), 1.0), saturate(post.depthOfField.x), sides,
            full >= clear};
    }
    float focus = postCentreFocus(camera, depth, post);
    float share = saturate((focus - 100.0) / 900.0);
    return {
        focus, mix(100.0, 10000.0, share), mix(0.8, 0.56, share), sides == 0 ? 3u : sides, true};
}

// How much one depth blurs, 0 to 1. CK wiki: clear at the distance and full at the
// range; a distance past the range blurs the foreground. A modifier can pick the sides.
static inline float postFocusBlur(float range, PostFocus focus)
{
    float nearBlur = saturate((focus.clear - range) / focus.span);
    float farBlur = saturate((range - focus.clear) / focus.span);
    switch (focus.sides) {
    case 1:
        return nearBlur;
    case 2:
        return farBlur;
    case 3:
        return max(nearBlur, farBlur);
    default:
        return focus.farFirst ? farBlur : nearBlur;
    }
}

// Depth of field: two rings of eight taps, as wide as the pixel's blur. A tap that is
// itself sharp is skipped, so a sharp shape does not bleed into the blur around it.
static inline float3 postDepthOfField(
    float3 color,
    PostPixel pixel,
    bool sky,
    float3 camera,
    texture2d<float> scene,
    depth2d<float> depth,
    constant PostEffectUniforms &post)
{
    PostFocus focus = postFocusPlane(camera, depth, post);
    float skyBlur = postFocusBlur(1.0e9, focus) * post.depthOfFieldMode.x;
    float blur = sky ? skyBlur : postFocusBlur(distance(pixel.world, camera), focus);
    float amount = focus.strength * blur;
    if (amount <= 0.0) {
        return color;
    }
    float3 sum = color;
    float weight = 1.0;
    for (int ring = 1; ring <= 2; ++ring) {
        float reach = post.depthOfField.w * amount * float(ring) * 0.5;
        for (int tap = 0; tap < 8; ++tap) {
            float angle = (float(tap) + 0.5 * float(ring)) * 0.7853982;
            float2 tapUV = pixel.uv + float2(cos(angle), sin(angle)) * reach * pixel.texel;
            float tapDepth = depth.sample(postNearest, tapUV);
            float tapBlur =
                tapDepth >= 1.0
                    ? skyBlur
                    : postFocusBlur(
                          distance(postWorldPosition(tapUV, tapDepth, post), camera), focus);
            if (tapBlur <= 0.0) {
                continue;
            }
            sum += scene.sample(postLinear, tapUV).rgb;
            weight += 1.0;
        }
    }
    return sum / weight;
}

// The share of 9 depth taps around the sun that see the sky; 0 when it is off screen.
static inline float postSunVisibility(float2 sun, float2 texel, depth2d<float> depth)
{
    if (any(sun < 0.0) || any(sun > 1.0)) {
        return 0.0;
    }
    float open = 0.0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            float2 tapUV = sun + float2(dx, dy) * 6.0 * texel;
            open += depth.sample(postNearest, tapUV) >= 1.0 ? 1.0 : 0.0;
        }
    }
    return open / 9.0;
}

// Lens flare: soft ghost discs on the line from the sun through the screen centre, in
// the sun colour, while the sun is in view and not hidden.
static inline float3 postLensFlare(
    PostPixel pixel,
    constant FrameUniforms &frame,
    constant PostEffectUniforms &post,
    depth2d<float> depth)
{
    float2 sun = post.lensFlare.xy;
    float visible = postSunVisibility(sun, pixel.texel, depth);
    if (visible <= 0.0) {
        return 0.0;
    }
    constexpr float along[5] = {0.4, 0.7, 1.1, 1.5, 1.9};
    constexpr float size[5] = {0.05, 0.025, 0.08, 0.04, 0.12};
    constexpr float3 tint[5] = {
        float3(1.0, 0.8, 0.5), float3(0.6, 1.0, 0.7), float3(0.5, 0.7, 1.0), float3(1.0, 0.6, 0.9),
        float3(0.7, 0.8, 1.0)};
    float2 axis = float2(0.5) - sun;
    float3 sum = 0.0;
    for (int ghost = 0; ghost < 5; ++ghost) {
        float2 offset = (pixel.uv - (sun + axis * along[ghost])) * float2(post.lensFlare.w, 1.0);
        float edge = length(offset) / size[ghost];
        sum += tint[ghost] * (1.0 - smoothstep(0.6, 1.0, edge)) * 0.2;
    }
    float centred = 1.0 - saturate(length(axis) * 1.2);
    return toLinear(frame.sunColor) * sum * (visible * centred * post.lensFlare.z);
}

// Every effect the frame turned on, in order, over the colour of one pixel.
// What the post-effect compute passes wrote for the composite.
struct PostTracedMaps
{
    texture2d<float> occlusion;
    texture2d<float> indirect;
};

static inline float3 postApply(
    float3 color,
    PostPixel pixel,
    constant FrameUniforms &frame,
    constant PostEffectUniforms &post,
    texture2d<float> scene,
    depth2d<float> depth,
    PostTracedMaps traced,
    depth2d_array<float> shadowMap,
    sampler compare)
{
    bool sky = pixel.depth >= 1.0;
    if ((post.effects & PostEffectFlagDepthOfField) != 0) {
        color = postDepthOfField(color, pixel, sky, frame.cameraPosition, scene, depth, post);
    }
    if ((post.effects & PostEffectFlagIndirectLight) != 0 && !sky) {
        color += traced.indirect.sample(postNearest, pixel.uv).rgb;
    }
    if ((post.effects & PostEffectFlagAmbientOcclusion) != 0 && !sky) {
        // The game darkens the whole lit colour: sun, point lights, and ambient alike.
        float occlusion = traced.occlusion.sample(postNearest, pixel.uv).r;
        color = postOccludeUnderFog(color, occlusion, pixel.world, frame);
    }
    if ((post.effects & PostEffectFlagVolumetricLight) != 0) {
        color = postVolumetricLight(color, pixel, sky, frame, post, shadowMap, compare);
    }
    if ((post.effects & PostEffectFlagLensFlare) != 0) {
        color += postLensFlare(pixel, frame, post, depth);
    }
    return color;
}

#endif /* PostEffects_h */
