#ifndef ProjectedMaterial_h
#define ProjectedMaterial_h

#include "ShaderCommon.h"

// A directional material texture repeats every 512 units at UV scale 1; an OpenSky choice.
constant float projectedTile = 512.0;

// A static's directional material (STAT DNAM with a MATO): faces that point along the
// direction take its texture or single-pass colour. The falloff scale and bias shape the
// edge; the texture is laid on the world XY plane.
struct ProjectedLayer
{
    float3 albedo;
    float3 normal;
    float blend;
};

static ProjectedLayer projectedLayer(
    float3 world,
    float3 normal,
    constant DrawUniforms &draw,
    texture2d<float> diffuseMap,
    texture2d<float> normalMap,
    sampler trilinear)
{
    ProjectedLayer layer = {draw.projectedColor.rgb, normal, 0.0};
    float limit = draw.projectedDirection.w;
    float facing = dot(normal, draw.projectedDirection.xyz);
    float edge = (facing - limit) / max(1.0 - limit, 0.001);
    layer.blend = facing < limit
                      ? 0.0
                      : saturate(edge * draw.projectedParameters.x + draw.projectedParameters.y);
    if (draw.projectedParameters.w > 1.5) {
        float2 uv = world.xy * (draw.projectedParameters.z / projectedTile);
        layer.albedo = diffuseMap.sample(trilinear, uv).rgb;
        float2 xy = normalMap.sample(trilinear, uv).xy * 2.0 - 1.0;
        layer.normal = normalize(float3(xy, sqrt(saturate(1.0 - dot(xy, xy)))));
    }
    return layer;
}

#endif /* ProjectedMaterial_h */
