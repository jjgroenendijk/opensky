#include "ShaderCommon.h"

// Terrain splat path (docs/rendering/scene-drawing.md): per-quadrant draw blends the BTXT
// base diffuse with up to TerrainConstantMaxLayers ATXT layer diffuses by
// per-vertex VTXT opacities (UESP LAND: VTXT holds a 0.0-1.0 opacity per
// painted vertex of the 17x17 quadrant grid). Weights arrive as a second
// vertex stream (TerrainVertexLayout, Rendering/RenderMesh.swift). Lighting
// matches staticMeshFragment so terrain shades like static meshes.

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal [[attribute(VertexAttributeNormal)]];
    float2 texcoord [[attribute(VertexAttributeTexcoord)]];
    float4 color [[attribute(VertexAttributeColor)]];
    float4 weights0 [[attribute(VertexAttributeLayerWeights0)]];
    float4 weights1 [[attribute(VertexAttributeLayerWeights1)]];
} TerrainVertexIn;

typedef struct
{
    float4 position [[position]];
    float3 normal;
    float3 worldPosition;
    float2 texcoord;
    float4 color;
    float4 weights0;
    float4 weights1;
    /// World direction of +u, east (TerrainMeshBuilder UVs). +v is north.
    float3 tangent;
} TerrainVertexOut;

vertex TerrainVertexOut terrainVertex(
    TerrainVertexIn in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant TerrainDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]])
{
    TerrainVertexOut out;
    float4 world = draw.modelMatrix * float4(in.position, 1.0);
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (draw.normalMatrix * float4(in.normal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    out.color = in.color;
    out.weights0 = in.weights0;
    out.weights1 = in.weights1;
    out.tangent = (draw.modelMatrix * float4(1.0, 0.0, 0.0, 0.0)).xyz;
    return out;
}

/// Tangent-space normal from a TX01 texel. Z is rebuilt from XY, so a two-channel
/// map works too. Green points along +v (measured on the vanilla maps, docs/engine/terrain.md).
static float2 terrainNormalXY(float4 texel)
{
    return texel.rg * 2.0 - 1.0;
}

/// The blended layer normals bend the vertex normal. East is made orthogonal to it,
/// and north follows from the cross product.
static float3 terrainShadingNormal(TerrainVertexOut in, float2 blendedXY)
{
    float3 vertexNormal = normalize(in.normal);
    float3 tangent = normalize(in.tangent - vertexNormal * dot(in.tangent, vertexNormal));
    float3 bitangent = cross(vertexNormal, tangent);
    float z = sqrt(saturate(1.0 - dot(blendedXY, blendedXY)));
    return normalize(tangent * blendedXY.x + bitangent * blendedXY.y + vertexNormal * z);
}

fragment float4 terrainFragment(
    TerrainVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant TerrainDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device PointLightUniform *pointLights [[buffer(BufferIndexPointLights)]],
    texture2d<float> baseMap [[texture(TextureIndexDiffuse)]],
    array<texture2d<float>, TerrainConstantMaxLayers> layerMaps
    [[texture(TextureIndexTerrainLayer0)]],
    texture2d<float> baseNormalMap [[texture(TextureIndexTerrainBaseNormal)]],
    array<texture2d<float>, TerrainConstantMaxLayers> layerNormalMaps
    [[texture(TextureIndexTerrainLayerNormal0)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]],
    raytracing::instance_acceleration_structure rayScene
    [[buffer(BufferIndexRayScene), function_constant(rayTracedShadows)]])
{
    if (debugViewActive) {
        DebugSurface surface = {
            in.worldPosition, in.normal, in.texcoord,
            baseMap.calculate_unclamped_lod(trilinear, in.texcoord), uint(RenderLayerBitTerrain)};
        return debugViewColor(frame, surface);
    }
    // Start opaque base, then lerp each layer in over the running color in
    // ATXT layer order. Straight lerp by VTXT opacity is the plain reading of
    // the spec; the exact vanilla blend curve is UNCONFIRMED.
    float3 albedo = baseMap.sample(trilinear, in.texcoord).rgb;
    float weights[TerrainConstantMaxLayers] = {in.weights0.x, in.weights0.y, in.weights0.z,
                                               in.weights0.w, in.weights1.x, in.weights1.y,
                                               in.weights1.z, in.weights1.w};
    bool normalMaps = draw.normalMapsEnabled != 0;
    float2 normalXY =
        normalMaps ? terrainNormalXY(baseNormalMap.sample(trilinear, in.texcoord)) : float2(0.0);
    uint count = min(draw.layerCount, uint(TerrainConstantMaxLayers));
    for (uint layer = 0; layer < count; ++layer) {
        float weight = saturate(weights[layer]);
        float3 layerColor = layerMaps[layer].sample(trilinear, in.texcoord).rgb;
        albedo = mix(albedo, layerColor, weight);
        if (normalMaps) {
            float4 texel = layerNormalMaps[layer].sample(trilinear, in.texcoord);
            normalXY = mix(normalXY, terrainNormalXY(texel), weight);
        }
    }
    float3 normal = normalMaps ? terrainShadingNormal(in, normalXY) : normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float shadow = sunShadowFactor(in.worldPosition, frame, shadowMap, shadowSampler);
    if (rayTracedShadows) {
        float traced = rayTracedSunShadow(in.worldPosition, normalize(in.normal), frame, rayScene);
        if (rayShadowView) {
            return float4(float3(traced), 1.0);
        }
        shadow = min(shadow, traced);
    }
    float3 illumination =
        frame.sunColor * lambert * shadow + frame.ambientColor + directionalAmbient(normal, frame) +
        pointLighting(in.worldPosition, normal, pointLights, draw.pointLightCount);
    float3 lit = albedo * in.color.rgb * illumination;
    return float4(applyFog(lit, in.worldPosition, frame), 1.0);
}

// Water: WATR colors and shading over three scrolling noise layers. The game samples
// noise textures; OpenSky sums sine waves with the same wind, tile size, and slope
// (docs/rendering/water.md). Scene depth, when bound, sets the see-through depth.

typedef struct
{
    float4 position [[position]];
    float3 worldPosition;
} WaterVertexOut;

vertex WaterVertexOut waterVertex(
    StaticVertexIn in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant WaterDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]])
{
    WaterVertexOut out;
    float4 world = draw.modelMatrix * float4(in.position, 1.0);
    out.position = frame.viewProjectionMatrix * world;
    out.worldPosition = world.xyz;
    return out;
}

// Three waves per layer, spread around the wind direction, so no single crest repeats.
static float3 waterNormal(float2 xy, float time, constant WaterDrawUniforms &draw)
{
    constexpr float tau = 6.2831853;
    float2 slope = 0.0;
    float2 flowing = xy - draw.flowVelocity * time;
    for (int layer = 0; layer < 3; ++layer) {
        float tile = max(draw.uvScales[layer], 50.0);
        float strength = draw.amplitudes[layer] * 0.08;
        for (int wave = 0; wave < 3; ++wave) {
            float angle = draw.windDirections[layer] + (float(wave) - 1.0) * 0.6;
            float2 direction = float2(cos(angle), sin(angle));
            float waveLength = tile * (1.0 - 0.3 * float(wave));
            float phase = tau * (dot(direction, flowing) / waveLength -
                                 draw.windSpeeds[layer] * time * (1.0 + 0.4 * float(wave)));
            slope += direction * (strength * cos(phase));
        }
    }
    return normalize(float3(-slope, 1.0));
}

fragment float4 waterFragment(
    WaterVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant WaterDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    depth2d<float> sceneDepth [[texture(TextureIndexWaterDepth)]])
{
    if (debugViewActive) {
        // A water plane is flat and untextured, so the normal is the plane's
        // own up and there is no meaningful texcoord or mip level to report.
        DebugSurface surface = {
            in.worldPosition, float3(0.0, 0.0, 1.0), float2(0.0), 0.0, uint(RenderLayerBitWater)};
        return debugViewColor(frame, surface);
    }
    float3 toCamera = frame.cameraPosition - in.worldPosition;
    float3 view = normalize(toCamera);
    float3 normal = waterNormal(in.worldPosition.xy, frame.animationTime, draw);
    if (view.z < 0.0) {
        normal = -normal;
    }

    // Water column under this pixel, straight down and along the view ray. With no
    // scene depth, a middle depth keeps the surface half see-through.
    float columnDepth = draw.depthAndSun.z * 0.7;
    float rayDepth = columnDepth;
    if (draw.depthAndSun.w > 0.5) {
        float stored = sceneDepth.read(uint2(in.position.xy));
        float behind = draw.depthUnproject.y / (stored + draw.depthUnproject.x);
        float facing = max(dot(-view, frame.cameraForward), 0.05);
        float surfaceDepth = dot(-toCamera, frame.cameraForward);
        rayDepth = max(behind - surfaceDepth, 0.0) / facing;
        columnDepth = rayDepth * abs(view.z);
    }
    float deepness = smoothstep(
        draw.depthAndSun.y, max(draw.depthAndSun.z, draw.depthAndSun.y + 1.0), columnDepth);
    float3 body = mix(draw.shallowColor, draw.deepColor, deepness);

    float baseReflect = clamp(draw.surface.y, 0.02, 1.0);
    float fresnel = baseReflect + (1.0 - baseReflect) * pow(1.0 - saturate(dot(normal, view)), 5.0);
    float reflection = saturate(fresnel * draw.surface.z);
    float3 sky = mix(draw.reflectionColor, frame.fogFarColor, 0.35);
    float3 color = mix(body * (frame.ambientColor + frame.sunColor * 0.6), sky, reflection);

    float3 mirrored = reflect(-view, normal);
    float sunAlign = saturate(dot(mirrored, -frame.sunDirection));
    float specular = pow(sunAlign, max(draw.surface.w * 0.25, 8.0)) * draw.depthAndSun.x;
    color += frame.sunColor * specular;

    // Shallow water shows the ground through it; deep or edge-on water hides it.
    float seeThrough = 1.0 - smoothstep(0.0, max(draw.depthAndSun.z, 1.0) * 2.0, rayDepth);
    float bodyAlpha = mix(1.0, draw.surface.x, seeThrough);
    float alpha = saturate(max(bodyAlpha, reflection) + specular);
    return float4(applyFog(color, in.worldPosition, frame), alpha);
}
