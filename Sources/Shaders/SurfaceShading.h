#pragma once

// Lit-mesh surface terms past the diffuse. The model follows NifSkope's open GLSL
// shaders (sk_default, sk_msn, sk_multilayer): docs/rendering/surface-shading.md.

#include "ShaderCommon.h"

static inline float3x3 upper3x3(float4x4 matrix)
{
    return float3x3(matrix[0].xyz, matrix[1].xyz, matrix[2].xyz);
}

static inline void setBasis(thread StaticVertexOut &out, float3x3 basis)
{
    out.basisX = basis[0];
    out.basisY = basis[1];
    out.basisZ = basis[2];
}

static inline bool hasTerm(uint terms, ShadingTerm term)
{
    return (terms & uint(term)) != 0;
}

// Tangent along +u and bitangent along +v, from screen derivatives, so the
// vertex layout needs no tangents. Mirrored UVs come out right by construction.
static float3x3 cotangentFrame(float3 normal, float3 position, float2 uv)
{
    float3 dp1 = dfdx(position);
    float3 dp2 = dfdy(position);
    float2 duv1 = dfdx(uv);
    float2 duv2 = dfdy(uv);
    float3 dp2perp = cross(dp2, normal);
    float3 dp1perp = cross(normal, dp1);
    float3 tangent = dp2perp * duv1.x + dp1perp * duv2.x;
    float3 bitangent = dp2perp * duv1.y + dp1perp * duv2.y;
    float scale = rsqrt(max(max(dot(tangent, tangent), dot(bitangent, bitangent)), 1e-20));
    return float3x3(tangent * scale, bitangent * scale, normal);
}

// The game blends in gamma space, so both inputs go to gamma and back.
static float3 overlayGamma(float3 base, float3 blend)
{
    float3 low = 2.0 * base * blend;
    float3 high = 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
    return select(high, low, base < 0.5);
}

static inline float3 toGamma(float3 linearColour)
{
    return pow(max(linearColour, 0.0), 1.0 / 2.2);
}

static inline float3 toLinear(float3 gamma)
{
    return pow(max(gamma, 0.0), 2.2);
}

// What one light adds. Each sum is later scaled by its own texture or colour.
struct LightSums
{
    float3 diffuse;
    float3 specular;
    float3 back;
    float3 rim;
    float3 soft;
};

struct LightGeometry
{
    float3 normal;
    float3 toEye;
    float gloss;
    float softWrap;
    float rimPower;
};

static void
addLight(thread LightSums &sums, LightGeometry geometry, float3 toLight, float3 colour, uint terms)
{
    float3 n = geometry.normal;
    float facing = dot(n, toLight);
    float lambert = max(facing, 0.0);
    sums.diffuse += colour * lambert;
    if (hasTerm(terms, ShadingTermSpecular)) {
        float3 halfway = normalize(toLight + geometry.toEye);
        sums.specular +=
            colour * pow(max(dot(n, halfway), 0.0), geometry.gloss) * step(0.0, facing);
    }
    if (hasTerm(terms, ShadingTermBackLighting)) {
        sums.back += colour * max(-facing, 0.0);
    }
    if (hasTerm(terms, ShadingTermRimLighting)) {
        float edge = pow(1.0 - max(dot(n, geometry.toEye), 0.0), geometry.rimPower);
        sums.rim += colour * edge * smoothstep(-0.2, 1.0, dot(-toLight, geometry.toEye));
    }
    if (hasTerm(terms, ShadingTermSoftLighting)) {
        float wrap = max((facing + geometry.softWrap) / (1.0 + geometry.softWrap), 0.0);
        float soft = wrap * smoothstep(1.0, 0.0, lambert) * sqrt(saturate(geometry.softWrap));
        sums.soft += colour * soft;
    }
}

static void addPointLights(
    thread LightSums &sums,
    LightGeometry geometry,
    float3 worldPosition,
    const device PointLightUniform *lights,
    uint count,
    uint terms)
{
    for (uint index = 0; index < count; ++index) {
        float3 toLight = lights[index].positionRadius.xyz - worldPosition;
        float distanceToLight = length(toLight);
        float radius = max(lights[index].positionRadius.w, 0.0001);
        float radial = saturate(1.0 - distanceToLight / radius);
        float attenuation = pow(radial, max(lights[index].colorFalloff.w, 0.01));
        float3 direction = toLight / max(distanceToLight, 0.0001);
        addLight(sums, geometry, direction, lights[index].colorFalloff.rgb * attenuation, terms);
    }
}

// Skyrim cube maps are DirectX cubes: Y up and left-handed. The world is Z up and
// right-handed, so swapping Y and Z converts both at once.
static inline float3 cubeDirection(float3 world)
{
    return float3(world.x, world.z, world.y);
}

// sk_multilayer's inner-layer lookup: the view ray bends at the surface and
// reaches the inner layer `thickness` texels down. The game assumes a 1024 map.
static float2 innerLayerCoordinate(
    float2 uv, float3 toEyeTangent, float3 normalTangent, constant DrawUniforms &draw, float alpha)
{
    float3 mixedNormal =
        normalize(mix(float3(0, 0, 1), normalTangent, saturate(draw.multiLayer.y)));
    float3 reflected = reflect(-toEyeTangent, mixedNormal);
    float3 transmitted = float3(reflected.xy, -reflected.z);
    float depth = draw.multiLayer.x * alpha / max(abs(transmitted.z), 0.0001);
    float2 texel = 1.0 / (1024.0 * max(draw.multiLayer.zw, 0.0001));
    return (uv + texel * depth * transmitted.xy) * draw.multiLayer.zw;
}
