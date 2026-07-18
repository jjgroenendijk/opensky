// Static-mesh shaders. Vertex layout comes from ShaderTypes.h attribute
// enums and StaticVertexLayout.vertexDescriptor() (Rendering/RenderMesh.swift).

#include <metal_stdlib>
#include <simd/simd.h>

#import "ShaderTypes.h"

using namespace metal;

static float3 directionalAmbient(float3 normal, constant FrameUniforms &frame)
{
    float3 weights = abs(normal);
    weights /= max(weights.x + weights.y + weights.z, 0.0001);
    float3 x = normal.x >= 0.0
        ? frame.directionalAmbientPositiveX : frame.directionalAmbientNegativeX;
    float3 y = normal.y >= 0.0
        ? frame.directionalAmbientPositiveY : frame.directionalAmbientNegativeY;
    float3 z = normal.z >= 0.0
        ? frame.directionalAmbientPositiveZ : frame.directionalAmbientNegativeZ;
    return x * weights.x + y * weights.y + z * weights.z;
}

static float3 pointLighting(
    float3 worldPosition,
    float3 normal,
    const device PointLightUniform *lights,
    uint count)
{
    float3 sum = 0.0;
    for (uint index = 0; index < count; ++index) {
        float3 toLight = lights[index].positionRadius.xyz - worldPosition;
        float distanceToLight = length(toLight);
        float radius = max(lights[index].positionRadius.w, 0.0001);
        float radial = saturate(1.0 - distanceToLight / radius);
        float attenuation = pow(radial, max(lights[index].colorFalloff.w, 0.01));
        float lambert = saturate(dot(normal, toLight / max(distanceToLight, 0.0001)));
        sum += lights[index].colorFalloff.rgb * attenuation * lambert;
    }
    return sum;
}

static float3 applyFog(float3 color, float3 worldPosition, constant FrameUniforms &frame)
{
    if (frame.fogEnabled == 0) {
        return color;
    }
    float distanceToCamera = distance(worldPosition, frame.cameraPosition);
    float range = max(frame.fogDistances.y - frame.fogDistances.x, 0.0001);
    float linear = saturate((distanceToCamera - frame.fogDistances.x) / range);
    float amount = pow(linear, max(frame.fogDistances.z, 0.01)) * frame.fogDistances.w;
    float3 fogColor = mix(frame.fogNearColor, frame.fogFarColor, linear);
    return mix(color, fogColor, saturate(amount));
}

// Procedural exterior sky: fullscreen triangle, time-of-day palette,
// horizon band, sun disc. Weather/CLMT sampling remains future work.

typedef struct
{
    float4 position [[position]];
    float2 uv;
} SkyVertexOut;

vertex SkyVertexOut skyVertex(uint vertexID [[vertex_id]])
{
    float2 positions[3] = {
        float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)
    };
    SkyVertexOut out;
    out.position = float4(positions[vertexID], 1.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

fragment float4 skyFragment(
    SkyVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]])
{
    float hour = fmod(frame.timeOfDayHours + 24.0, 24.0);
    float sunrise = smoothstep(5.0, 8.0, hour);
    float sunset = 1.0 - smoothstep(18.0, 21.0, hour);
    float daylight = sunrise * sunset;
    float dawnDistance = min(abs(hour - 6.0), abs(hour - 19.0));
    float twilight = exp(-0.5 * pow(dawnDistance / 1.2, 2.0));

    float3 nightUpper = float3(0.008, 0.015, 0.045);
    float3 dayUpper = float3(0.10, 0.34, 0.72);
    float3 nightHorizon = float3(0.025, 0.035, 0.075);
    float3 dayHorizon = float3(0.58, 0.74, 0.88);
    float3 warmHorizon = float3(0.95, 0.33, 0.12);
    float3 upper = mix(nightUpper, dayUpper, daylight);
    float3 horizon = mix(nightHorizon, dayHorizon, daylight);
    horizon = mix(horizon, warmHorizon, saturate(twilight * 0.7));
    float height = smoothstep(0.05, 0.92, in.uv.y);
    float3 color = mix(horizon, upper, height);

    float sunPhase = saturate((hour - 6.0) / 12.0);
    float2 sunCenter = float2(
        0.08 + sunPhase * 0.84,
        0.38 + sin(sunPhase * 3.14159265) * 0.36
    );
    float sunDistance = distance(in.uv, sunCenter);
    float disc = (1.0 - smoothstep(0.012, 0.02, sunDistance)) * daylight;
    float glow = exp(-sunDistance * 32.0) * daylight;
    color += float3(1.0, 0.72, 0.36) * glow * 0.22;
    color = mix(color, float3(1.0, 0.92, 0.68), disc);
    return float4(color, 1.0);
}

// Static-mesh path (docs/todo.md 2.6): diffuse * (directional sun + ambient),
// vertex color as tint (Skyrim bakes AO there). Alpha-test pipeline variant
// selected via function constant so opaque draws pay nothing for it.

constant bool alphaTestEnabled [[function_constant(FunctionConstantAlphaTest)]];

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal [[attribute(VertexAttributeNormal)]];
    float2 texcoord [[attribute(VertexAttributeTexcoord)]];
    float4 color [[attribute(VertexAttributeColor)]];
} StaticVertexIn;

typedef struct
{
    float4 position [[position]];
    float3 normal;
    float3 worldPosition;
    float2 texcoord;
    float4 color;
} StaticVertexOut;

// Instanced (todo 3.2): matrices come from the per-instance transform
// array, bound at the draw group's base offset — instance_id starts at 0
// per draw call, so it indexes straight into the group's visible instances.
// Shared by the opaque and alpha-test pipeline variants (the function
// constant only specializes the fragment side).
vertex StaticVertexOut staticMeshVertex(
    StaticVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant DrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]])
{
    StaticVertexOut out;
    const device InstanceTransform &instance = instances[instanceID];
    float4 world = instance.modelMatrix * float4(in.position, 1.0);
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (instance.normalMatrix * float4(in.normal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    out.color = in.color;
    return out;
}

fragment float4 staticMeshFragment(
    StaticVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant DrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device PointLightUniform *pointLights [[buffer(BufferIndexPointLights)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    float4 diffuse = diffuseMap.sample(trilinear, in.texcoord);
    float alpha = diffuse.a * in.color.a * draw.materialAlpha;
    if (alphaTestEnabled && alpha < draw.alphaThreshold) {
        discard_fragment();
    }
    float3 normal = normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float3 illumination = frame.sunColor * lambert + frame.ambientColor
        + directionalAmbient(normal, frame)
        + pointLighting(in.worldPosition, normal, pointLights, draw.pointLightCount);
    float3 lit = diffuse.rgb * in.color.rgb * illumination;
    return float4(applyFog(lit, in.worldPosition, frame), alpha);
}

// Terrain splat path (docs/todo.md 3.1): per-quadrant draw blends the BTXT
// base diffuse with up to TerrainConstantMaxLayers ATXT layer diffuses by
// per-vertex VTXT opacities (UESP LAND: VTXT holds a 0.0-1.0 opacity per
// painted vertex of the 17x17 quadrant grid). Weights arrive as a second
// vertex stream (TerrainVertexLayout, Rendering/RenderMesh.swift). Lighting
// matches staticMeshFragment so terrain shades like the M2 buildings.

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
    return out;
}

fragment float4 terrainFragment(
    TerrainVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant TerrainDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device PointLightUniform *pointLights [[buffer(BufferIndexPointLights)]],
    texture2d<float> baseMap [[texture(TextureIndexDiffuse)]],
    array<texture2d<float>, TerrainConstantMaxLayers>
        layerMaps [[texture(TextureIndexTerrainLayer0)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    // Start opaque base, then lerp each layer in over the running color in
    // ATXT layer order. Straight lerp by VTXT opacity is the plain reading of
    // the spec; the exact vanilla blend curve is UNCONFIRMED.
    float3 albedo = baseMap.sample(trilinear, in.texcoord).rgb;
    float weights[TerrainConstantMaxLayers] = {
        in.weights0.x, in.weights0.y, in.weights0.z, in.weights0.w,
        in.weights1.x, in.weights1.y, in.weights1.z, in.weights1.w
    };
    uint count = min(draw.layerCount, uint(TerrainConstantMaxLayers));
    for (uint layer = 0; layer < count; ++layer) {
        float3 layerColor = layerMaps[layer].sample(trilinear, in.texcoord).rgb;
        albedo = mix(albedo, layerColor, saturate(weights[layer]));
    }
    float3 normal = normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float3 illumination = frame.sunColor * lambert + frame.ambientColor
        + directionalAmbient(normal, frame)
        + pointLighting(in.worldPosition, normal, pointLights, draw.pointLightCount);
    float3 lit = albedo * in.color.rgb * illumination;
    return float4(applyFog(lit, in.worldPosition, frame), 1.0);
}

// Cell water: flat geometry, animated interference ripples in color, WATR
// shallow/deep/reflection palette, camera-angle Fresnel, straight alpha.

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

fragment float4 waterFragment(
    WaterVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant WaterDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]])
{
    float2 phase = in.worldPosition.xy * 0.006;
    float ripple = sin(phase.x + frame.animationTime * 1.3)
        * cos(phase.y - frame.animationTime * 0.9);
    float distanceMix = smoothstep(
        1000.0, 12000.0, distance(in.worldPosition.xy, frame.cameraPosition.xy)
    );
    float3 base = mix(draw.shallowColor, draw.deepColor, distanceMix * 0.65 + 0.15);
    float3 viewDirection = normalize(frame.cameraPosition - in.worldPosition);
    float fresnel = pow(1.0 - saturate(abs(viewDirection.z)), 3.0);
    float3 color = mix(base, draw.reflectionColor, saturate(0.18 + fresnel * 0.55));
    color *= 0.94 + ripple * 0.06;
    return float4(color, 0.64);
}
