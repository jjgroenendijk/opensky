#ifndef SnowShading_h
#define SnowShading_h

#include "ShaderCommon.h"

// Snow under the improved snow option, as the game draws it on snow ground and on
// snow-material meshes (docs/engine/terrain.md#snow-ground).

// A white sheen at grazing angles, from the vertex and the mapped normal.
static float snowRim(float3 toEye, float3 vertexNormal, float3 normal)
{
    float geometry = pow(1.0 - saturate(dot(vertexNormal, toEye)), 3.0);
    float mapped = pow(1.0 - saturate(dot(normal, toEye)), 2.0);
    return geometry * mapped * 0.3;
}

// A permutation polynomial modulo 289 hashes a lattice point.
static float snowPermute(float value)
{
    float wrapped = value - floor(value / 289.0) * 289.0;
    float mixed = (wrapped * 34.0 + 1.0) * wrapped;
    return mixed - floor(mixed / 289.0) * 289.0;
}

static float snowCorner(float3 cell, float3 offset)
{
    constexpr float3 gradients[12] = {float3(1, 1, 0),   float3(-1, 1, 0),  float3(1, -1, 0),
                                      float3(-1, -1, 0), float3(1, 0, 1),   float3(-1, 0, 1),
                                      float3(1, 0, -1),  float3(-1, 0, -1), float3(0, 1, 1),
                                      float3(0, -1, 1),  float3(0, 1, -1),  float3(0, -1, -1)};
    float falloff = max(0.6 - dot(offset, offset), 0.0);
    float hash = snowPermute(snowPermute(snowPermute(cell.x) + cell.y) + cell.z);
    uint index = uint(hash - floor(hash / 12.0) * 12.0);
    return pow(falloff, 4.0) * dot(gradients[min(index, 11u)], offset);
}

// Simplex noise in -1...1 over a world position.
static float snowNoise(float3 point)
{
    float3 cell = floor(point + dot(point, float3(1.0 / 3.0)));
    float3 offset0 = point - cell + dot(cell, float3(1.0 / 6.0));
    float3 larger = step(offset0.yzx, offset0.xyz);
    float3 step1 = min(larger, 1.0 - larger.zxy);
    float3 step2 = max(larger, 1.0 - larger.zxy);
    float sum = snowCorner(cell, offset0) + snowCorner(cell + step1, offset0 - step1 + 1.0 / 6.0) +
                snowCorner(cell + step2, offset0 - step2 + 1.0 / 3.0) +
                snowCorner(cell + 1.0, offset0 - 0.5);
    return clamp(sum * 32.0, -1.0, 1.0);
}

// The sun glints: noise squared, cut below 0.85, half lit in shadow at a quarter, gone by
// 1000 units, in the sun's colour.
static float3 snowSparkle(float3 world, float shadow, constant FrameUniforms &frame)
{
    float value = saturate((snowNoise(world * 6.0 * 0.07) + 1.0) * 0.5);
    float sparkle = value * value;
    if (sparkle < 0.85) {
        return 0.0;
    }
    sparkle *= shadow + (1.0 - shadow) * 0.25;
    sparkle *= 1.0 - smoothstep(0.0, 1000.0, distance(world, frame.cameraPosition));
    return frame.sunColor * sparkle;
}

// An opaque pixel stores 0 in the scene alpha where snow covers it. The game turns ambient
// occlusion off wherever the snow mask is above zero; the occlusion pass reads this.
static inline float snowCoverageAlpha(float snowMask)
{
    return snowMask > 0.0 ? 0.0 : 1.0;
}

#endif /* SnowShading_h */
