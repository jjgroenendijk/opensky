// Water draw types shared between Metal shaders and Swift. ShaderTypes.h includes this
// file after the constants it uses.

#ifndef WaterShaderTypes_h
#define WaterShaderTypes_h

#include "ShaderTypes.h"

/// One water surface. Colors and shading decode from WATR DNAM (docs/formats/water.md).
typedef struct
{
    matrix_float4x4 modelMatrix;
    vector_float3 shallowColor;
    vector_float3 deepColor;
    vector_float3 reflectionColor;
    /// x=opacity, y=fresnel amount, z=reflectivity, w=sun specular power.
    vector_float4 surface;
    /// x=sun specular magnitude, y=fog near, z=fog far, w=1 when scene depth is bound.
    vector_float4 depthAndSun;
    /// Per noise layer: direction in radians, speed in tiles per second, tile size, slope.
    /// amplitudes.w is the noise falloff distance; below 0, the noise does not fade.
    vector_float4 windDirections;
    vector_float4 windSpeeds;
    vector_float4 uvScales;
    vector_float4 amplitudes;
    vector_float2 flowVelocity;
    /// Projection terms (m22, m32): view depth = y / (ndcDepth + x).
    vector_float2 depthUnproject;
    /// x refraction magnitude, y sun sparkle magnitude, z sun sparkle power, w 1 when the
    /// three noise maps are bound at TextureIndexSurfaceNormal, Glow, and Detail.
    vector_float4 detail;
    /// Displacement rings: starting size, force, velocity, dampener.
    vector_float4 displacement;
    /// x displacement falloff, y rain 0 to 1, z live ring count, w 1 when the scene colour
    /// copy is bound for refraction.
    vector_float4 rings;
    /// x 1 when the cell's flow map and the flow noise are bound at
    /// TextureIndexWaterFlowMap and TextureIndexWaterFlowNoise, y the flow map scale.
    vector_float4 flow;
    /// Each ring: x, y, age in seconds, strength.
    vector_float4 ripples[WaterConstantMaxRipples];
} WaterDrawUniforms;

#endif /* WaterShaderTypes_h */
