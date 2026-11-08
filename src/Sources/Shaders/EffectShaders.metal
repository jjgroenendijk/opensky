#include "ShaderCommon.h"
#include "EffectShading.h"

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
    float2 turn = particle.rotation.xy;
    float2 turned =
        float2(corner.x * turn.x - corner.y * turn.y, corner.x * turn.y + corner.y * turn.x);
    float3 world =
        particle.positionSize.xyz +
        (frame.cameraRight * turned.x + frame.cameraUp * turned.y) * particle.positionSize.w;
    ParticleVertexOut out;
    out.position = frame.viewProjectionMatrix * float4(world, 1.0);
    out.worldPosition = world;
    float2 atlasUV = corner * 0.5 + 0.5;
    out.texcoord = particle.uvRect.xy + atlasUV * particle.uvRect.zw;
    out.color = particle.color;
    return out;
}

// A ribbon band (docs/rendering/particles.md#ribbons): the instance holds the start point
// and width in positionSize, the end point and width in rotation, and the texture coordinate
// along the band in uvRect.xy; uvRect.z set runs it along the texture's V.
vertex ParticleVertexOut ribbonVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    const device ParticleInstance *particles [[buffer(BufferIndexParticleInstances)]])
{
    constexpr float2 corners[6] = {float2(-1, 0), float2(1, 0), float2(-1, 1),
                                   float2(-1, 1), float2(1, 0), float2(1, 1)};
    const device ParticleInstance &band = particles[instanceID];
    float2 corner = corners[vertexID];
    float3 start = band.positionSize.xyz;
    float3 end = band.rotation.xyz;
    float3 point = mix(start, end, corner.y);
    float width = mix(band.positionSize.w, band.rotation.w, corner.y);
    float3 along = end - start;
    float3 toEye = frame.cameraPosition - point;
    float3 side = cross(along, toEye);
    float sideLength = length(side);
    side = sideLength > 1e-5 ? side / sideLength : frame.cameraRight;
    float3 world = point + side * (corner.x * width * 0.5);
    ParticleVertexOut out;
    out.position = frame.viewProjectionMatrix * float4(world, 1.0);
    out.worldPosition = world;
    float alongUV = mix(band.uvRect.x, band.uvRect.y, corner.y);
    float acrossUV = corner.x * 0.5 + 0.5;
    out.texcoord = band.uvRect.z > 0.5 ? float2(acrossUV, alongUV) : float2(alongUV, acrossUV);
    out.color = band.color;
    return out;
}

// Rain occlusion: the top-down view keeps the highest surface over each texel, so a
// drop below it, by more than a little, is under a roof.
static bool
precipitationOccluded(float3 world, constant FrameUniforms &frame, depth2d_array<float> auxiliary)
{
    if (frame.precipitationOcclusionEnabled == 0) {
        return false;
    }
    float4 view = frame.precipitationOcclusion * float4(world, 1.0);
    float2 uv = view.xy * float2(0.5, -0.5) + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0) || view.z <= 0.0 || view.z >= 1.0) {
        return false;
    }
    constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
    float roof = auxiliary.sample(
        nearest, uv * (float(ShadowConstantPrecipitationResolution) / ShadowConstantAuxiliarySize),
        ShadowConstantPrecipitationSlice);
    return view.z > roof + 0.002;
}

// A particle shades like an effect shape that faces the eye: the particle colour is
// its vertex colour (docs/rendering/particles.md).
fragment float4 particleFragment(
    ParticleVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant ParticleEffectUniforms &effect [[buffer(BufferIndexDrawUniforms)]],
    const device PointLightUniform *pointLights [[buffer(BufferIndexPointLights)]],
    texture2d<float> sourceMap [[texture(TextureIndexDiffuse)]],
    texture2d<float> palette [[texture(TextureIndexEffectPalette)]],
    depth2d<float> sceneDepth [[texture(TextureIndexSceneDepth)]],
    depth2d_array<float> auxiliary [[texture(TextureIndexAuxiliaryShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    if ((effect.flags & EffectFlagPrecipitation) != 0 &&
        precipitationOccluded(in.worldPosition, frame, auxiliary)) {
        discard_fragment();
    }
    float3 toEye = normalize(frame.cameraPosition - in.worldPosition);
    float4 shaded = effectShade(
        sourceMap.sample(trilinear, in.texcoord), in.color, toEye, toEye,
        EffectTerms{effect.flags, effect.falloff, effect.baseColor, effect.baseColorScale},
        palette);
    float alpha = shaded.a;
    if ((effect.flags & EffectFlagSoft) != 0) {
        alpha *=
            softEffectFade(in.position.xy, in.worldPosition, effect.softDepth, frame, sceneDepth);
    }
    if (alpha <= 0.002) {
        discard_fragment();
    }
    EffectLightInput light = {effect.flags, effect.lighting.x, in.worldPosition, toEye,
                              toEye,        effect.emittance};
    float3 rgb = shaded.rgb * effectLight(light, frame, pointLights, effect.pointLightCount);
    bool adds = effect.lighting.y > 0.5;
    float3 fogged = adds ? applyAdditiveFog(rgb, in.worldPosition, frame)
                         : applyFog(rgb, in.worldPosition, frame);
    return float4(fogged, alpha);
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

static float4 litDecal(
    float4 diffuse,
    float3 normal,
    float3 world,
    constant FrameUniforms &frame,
    depth2d_array<float> shadowMap,
    depth2d_array<float> auxiliary,
    sampler shadowSampler)
{
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float shadow = sunShadowFactor(world, frame, shadowMap, auxiliary, shadowSampler);
    float3 illumination =
        frame.sunColor * lambert * shadow + baseAmbient(frame) + directionalAmbient(normal, frame);
    return float4(applyFog(diffuse.rgb * toLinear(illumination), world, frame), diffuse.a);
}

fragment float4 decalFragment(
    DecalVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    depth2d_array<float> auxiliary [[texture(TextureIndexAuxiliaryShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]])
{
    float4 diffuse = diffuseMap.sample(trilinear, in.texcoord) * in.color;
    if (diffuse.a <= 0.002) {
        discard_fragment();
    }
    return litDecal(
        diffuse, normalize(in.normal), in.worldPosition, frame, shadowMap, auxiliary,
        shadowSampler);
}

// Projected decal: a box around the decal. Each pixel the box covers reads the scene
// depth, rebuilds the surface point there, and draws when that point is inside the
// box, so the mark wraps around a curved body.

typedef struct
{
    float4 position [[position]];
    float3 worldPosition;
    /// Outward normal of the box face, to keep only the far faces.
    float3 faceNormal [[flat]];
    uint decal [[flat]];
} ProjectedDecalVertexOut;

static float3 projectedDecalDepthAxis(const device DecalInstance &decal)
{
    return normalize(cross(decal.axisU.xyz, decal.axisV.xyz)) * decal.center.w;
}

vertex ProjectedDecalVertexOut projectedDecalVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    const device DecalInstance *decals [[buffer(BufferIndexParticleInstances)]])
{
    constexpr float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1),
                                   float2(-1, 1),  float2(1, -1), float2(1, 1)};
    uint face = vertexID / 6;
    uint axis = face / 2;
    float side = (face & 1) != 0 ? 1.0 : -1.0;
    float2 corner = corners[vertexID % 6];
    float3 local = axis == 0   ? float3(side, corner.x, corner.y)
                   : axis == 1 ? float3(corner.x, side, corner.y)
                               : float3(corner.x, corner.y, side);
    const device DecalInstance &decal = decals[instanceID];
    float3 depthAxis = projectedDecalDepthAxis(decal);
    float3 world = decal.center.xyz + decal.axisU.xyz * local.x + decal.axisV.xyz * local.y +
                   depthAxis * local.z;
    float3 axes[3] = {decal.axisU.xyz, decal.axisV.xyz, depthAxis};
    ProjectedDecalVertexOut out;
    out.position = frame.viewProjectionMatrix * float4(world, 1.0);
    out.worldPosition = world;
    out.faceNormal = axes[axis] * side;
    out.decal = instanceID;
    return out;
}

fragment float4 projectedDecalFragment(
    ProjectedDecalVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    const device DecalInstance *decals [[buffer(BufferIndexParticleInstances)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    depth2d<float> sceneDepth [[texture(TextureIndexSceneDepth)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    depth2d_array<float> auxiliary [[texture(TextureIndexAuxiliaryShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]])
{
    float3 toBox = in.worldPosition - frame.cameraPosition;
    float own = dot(toBox, frame.cameraForward);
    float4 unproject = frame.sceneDepthUnproject;
    // Only the far faces draw, so each pixel blends once, also with the camera inside.
    if (dot(in.faceNormal, toBox) < 0.0 || unproject.z < 0.5 || own <= 0.0) {
        discard_fragment();
    }
    float stored = sceneDepth.read(uint2(in.position.xy));
    float behind = unproject.y / (stored + unproject.x);
    float3 surface = frame.cameraPosition + toBox * (behind / own);
    const device DecalInstance &decal = decals[in.decal];
    float3 depthAxis = projectedDecalDepthAxis(decal);
    float3 offset = surface - decal.center.xyz;
    float3 local = float3(
        dot(offset, decal.axisU.xyz) / length_squared(decal.axisU.xyz),
        dot(offset, decal.axisV.xyz) / length_squared(decal.axisV.xyz),
        dot(offset, depthAxis) / length_squared(depthAxis));
    if (any(abs(local) > 1.0)) {
        discard_fragment();
    }
    float2 texcoord =
        decal.uvRect.xy + float2(local.x * 0.5 + 0.5, 0.5 - local.y * 0.5) * decal.uvRect.zw;
    float4 diffuse = diffuseMap.sample(trilinear, texcoord) * decal.color;
    if (diffuse.a <= 0.002) {
        discard_fragment();
    }
    return litDecal(
        diffuse, normalize(depthAxis), surface, frame, shadowMap, auxiliary, shadowSampler);
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
