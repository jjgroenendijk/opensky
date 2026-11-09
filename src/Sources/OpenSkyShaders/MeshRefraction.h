#ifndef MeshRefraction_h
#define MeshRefraction_h

#include "SurfaceShading.h"

// Refraction strength 1 moves the scene by a tenth of the screen; fire refraction
// scrolls its normal map half a texture per second. Both are OpenSky choices.
constant float refractionReach = 0.1;
constant float fireRefractionScroll = 0.5;

struct RefractionInput
{
    float2 pixel;
    float2 uv;
    float fade;
    uint terms;
};

// The scene copy, bent by the normal map. Fire refraction scrolls the map upward, and
// the vertex and material alpha fade the bend out toward the shape's edges.
static float3 refracted(
    RefractionInput input,
    constant FrameUniforms &frame,
    constant DrawUniforms &draw,
    texture2d<float> normalMap,
    texture2d<float> scene,
    sampler trilinear)
{
    float2 uv = input.uv;
    if (hasTerm(input.terms, ShadingTermFireRefraction)) {
        uv.y += frame.animationTime * fireRefractionScroll;
    }
    float2 bend = normalMap.sample(trilinear, uv).xy * 2.0 - 1.0;
    float2 size = float2(scene.get_width(), scene.get_height());
    float reach = draw.lightingEffects.w * refractionReach * saturate(input.fade);
    constexpr sampler clamped(filter::linear, address::clamp_to_edge);
    return scene.sample(clamped, input.pixel / size + bend * reach).rgb;
}

#endif /* MeshRefraction_h */
