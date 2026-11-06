#ifndef ProjectedMaterial_h
#define ProjectedMaterial_h

#include "ShaderCommon.h"

// A directional material texture repeats every 512 units at UV scale 1; an OpenSky choice.
constant float projectedTile = 512.0;

// A static's directional material (STAT DNAM with a MATO): faces that point along the
// direction take its texture or single-pass colour, as the game draws it: the facing times
// the vertex alpha, past the max angle, gives a soft edge for a texture and a hard one for
// a colour. The texture is laid on the world XY plane (docs/rendering/surface-shading.md).
struct ProjectedLayer
{
    float3 albedo;
    float blend;
};

static ProjectedLayer projectedLayer(
    float3 world,
    float3 normal,
    float vertexAlpha,
    constant DrawUniforms &draw,
    texture2d<float> diffuseMap,
    sampler trilinear)
{
    ProjectedLayer layer = {draw.projectedColor.rgb, 0.0};
    float edge = dot(normal, draw.projectedDirection.xyz) * vertexAlpha - draw.projectedDirection.w;
    if (draw.projectedParameters.w > 1.5) {
        float2 uv = world.xy * (draw.projectedParameters.z / projectedTile);
        layer.albedo = diffuseMap.sample(trilinear, uv).rgb;
        layer.blend = smoothstep(-0.1, 0.1, edge);
    } else {
        layer.blend = edge > 0.0 ? 1.0 : 0.0;
    }
    return layer;
}

#endif /* ProjectedMaterial_h */
