#ifndef ProjectedMaterial_h
#define ProjectedMaterial_h

#include "ShaderCommon.h"

// A static's directional material (STAT DNAM with a MATO), as the game draws it: faces
// that point along the direction, past the max angle widened by the falloff and the edge
// noise, take the layer (docs/rendering/surface-shading.md#directional-materials).
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
    texture2d<float> noiseMap,
    sampler trilinear)
{
    uint kind = uint(draw.projectedParameters.w) & 3u;
    float cosine = draw.projectedDirection.w;
    float open = 1.0 - cosine;
    float2 uv = float2(world.y, -world.x);
    float noise = noiseMap.sample(trilinear, uv / max(draw.projectedColor.a, 1.0e-3)).r;
    float edge = dot(normal, draw.projectedDirection.xyz) * vertexAlpha -
                 (open * draw.projectedParameters.y + cosine) -
                 open * draw.projectedParameters.x * noise;
    ProjectedLayer layer = {draw.projectedColor.rgb, edge > 0.0 ? 1.0 : 0.0};
    if (kind >= 2u) {
        float3 texel =
            diffuseMap.sample(trilinear, uv / max(draw.projectedParameters.z, 1.0e-3)).rgb;
        // The single-pass map is tinted by the material colour; an overlay is not.
        layer.albedo = kind == 2u ? texel * draw.projectedColor.rgb : texel;
        layer.blend = kind == 2u ? smoothstep(-0.1, 0.1, edge) : (edge >= 0.0 ? 1.0 : 0.0);
    }
    return layer;
}

#endif /* ProjectedMaterial_h */
