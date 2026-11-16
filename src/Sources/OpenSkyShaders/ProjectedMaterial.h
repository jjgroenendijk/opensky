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

// The layer's texture coordinate: the world position in a frame across the direction.
// Straight up, as every single-pass layer is, this is the world (y, -x).
static float2 projectedUV(float3 world, float3 direction)
{
    float3 helper = abs(direction.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 across = normalize(helper - direction * dot(helper, direction));
    return float2(dot(world, across), dot(world, cross(direction, across)));
}

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
    float2 uv = projectedUV(world, draw.projectedDirection.xyz);
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

// The snow mask from the projected mode bits (DrawUniforms.projectedParameters.w).
// A drawn overlay pixel is snow when its material is; a single-pass layer gives its
// blend, plus the diffuse alpha on a snow-base mesh; a snow mesh alone gives its alpha.
static float projectedSnowMask(uint projected, float blend, float diffuseAlpha)
{
    uint kind = projected & 3u;
    bool material = (projected & 4u) != 0;
    bool mesh = (projected & 8u) != 0;
    bool base = (projected & 16u) != 0;
    float meshMask = mesh ? diffuseAlpha : 0.0;
    if (kind == 3u) {
        return blend > 0.0 ? (material ? 1.0 : 0.0) : meshMask;
    }
    if (kind != 0u && (material || mesh)) {
        return base ? min(1.0, diffuseAlpha + blend) : saturate(blend);
    }
    return meshMask;
}

#endif /* ProjectedMaterial_h */
