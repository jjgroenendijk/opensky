#pragma once

#include "ShaderCommon.h"

// Tree sway grows with height like a tilt; leaves flutter by their wind weight and fade
// with distance. The scales are OpenSky's (docs/rendering/trees.md).
constant float treeSwayTilt = 0.1;
constant float leafSideShare = 0.5;

static inline float3 treeWindOffset(
    float3 world,
    float weight,
    float3 origin,
    constant DrawUniforms &draw,
    constant FrameUniforms &frame)
{
    float4 motion = draw.windMotion;
    float speed = frame.treeWind.z;
    if (speed <= 0.0 || (motion.x <= 0.0 && motion.w <= 0.0)) {
        return 0.0;
    }
    float2 direction = frame.treeWind.xy;
    float phase = dot(origin.xy, float2(0.0013, 0.0021));
    float height = max(world.z - origin.z, 0.0);
    float time = frame.animationTime;
    float swing = 0.75 + 0.25 * sin(6.28318530718 * motion.y * time + phase);
    float3 offset = float3(direction * (motion.x * speed * treeSwayTilt * height * swing), 0.0);
    if (motion.w > 0.0) {
        float fade =
            saturate(1.0 - distance(origin, frame.cameraPosition) / max(frame.treeWind.w, 1.0));
        float wave =
            sin(6.28318530718 * motion.w * time + phase * 7.0 + (world.x + world.y) * 0.05);
        float flutter = motion.z * weight * speed * fade * wave;
        offset += float3(direction * flutter * leafSideShare, flutter);
    }
    return offset;
}
