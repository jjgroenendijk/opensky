#include "ShaderCommon.h"

// CPU particle path: six vertex_id corners per instance. Camera basis comes
// from FrameUniforms, so every quad remains billboarded without CPU rebuild.

typedef struct
{
    float4 position [[position]];
    float3 worldPosition;
    float2 texcoord;
    float4 color;
} ParticleVertexOut;

vertex ParticleVertexOut particleVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    const device ParticleInstance *particles [[buffer(BufferIndexParticleInstances)]])
{
    constexpr float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1),
                                   float2(-1, 1),  float2(1, -1), float2(1, 1)};
    const device ParticleInstance &particle = particles[instanceID];
    float2 corner = corners[vertexID];
    float3 world =
        particle.positionSize.xyz +
        (frame.cameraRight * corner.x + frame.cameraUp * corner.y) * particle.positionSize.w;
    ParticleVertexOut out;
    out.position = frame.viewProjectionMatrix * float4(world, 1.0);
    out.worldPosition = world;
    float2 atlasUV = corner * 0.5 + 0.5;
    out.texcoord = particle.uvRect.xy + atlasUV * particle.uvRect.zw;
    out.color = particle.color;
    return out;
}

fragment float4 particleFragment(
    ParticleVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    texture2d<float> sourceMap [[texture(TextureIndexDiffuse)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    float4 sample = sourceMap.sample(trilinear, in.texcoord) * in.color;
    if (sample.a <= 0.002) {
        discard_fragment();
    }
    return float4(applyFog(sample.rgb, in.worldPosition, frame), sample.a);
}

// Decals (docs/rendering/decals.md): a flat quad on the struck surface, lit by the
// sun and ambient with the surface normal, drawn after the opaque scene with a depth
// bias so it wins the depth test against the surface under it.

typedef struct
{
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 texcoord;
    float4 color;
} DecalVertexOut;

vertex DecalVertexOut decalVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    const device DecalInstance *decals [[buffer(BufferIndexParticleInstances)]])
{
    constexpr float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1),
                                   float2(-1, 1),  float2(1, -1), float2(1, 1)};
    const device DecalInstance &decal = decals[instanceID];
    float2 corner = corners[vertexID];
    float3 world = decal.center.xyz + decal.axisU.xyz * corner.x + decal.axisV.xyz * corner.y;
    DecalVertexOut out;
    out.position = frame.viewProjectionMatrix * float4(world, 1.0);
    out.worldPosition = world;
    out.normal = cross(decal.axisU.xyz, decal.axisV.xyz);
    out.texcoord =
        decal.uvRect.xy + float2(corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5) * decal.uvRect.zw;
    out.color = decal.color;
    return out;
}

fragment float4 decalFragment(
    DecalVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]])
{
    float4 diffuse = diffuseMap.sample(trilinear, in.texcoord) * in.color;
    if (diffuse.a <= 0.002) {
        discard_fragment();
    }
    float3 normal = normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float shadow = sunShadowFactor(in.worldPosition, frame, shadowMap, shadowSampler);
    float3 illumination =
        frame.sunColor * lambert * shadow + frame.ambientColor + directionalAmbient(normal, frame);
    return float4(applyFog(diffuse.rgb * illumination, in.worldPosition, frame), diffuse.a);
}

// Effect-shader membrane: an additive glow over the target's meshes, brighter at
// grazing angles (docs/rendering/visual-effects.md). Blending is one + one.
fragment float4 membraneFragment(
    StaticVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant MembraneUniforms &membrane [[buffer(BufferIndexMembraneUniforms)]])
{
    float3 toEye = normalize(frame.cameraPosition - in.worldPosition);
    float facing = saturate(abs(dot(normalize(in.normal), toEye)));
    float rim = pow(1.0 - facing, max(membrane.edge.a, 0.05));
    return float4(membrane.fill.rgb + membrane.edge.rgb * rim, 0.0);
}
