#include "ShaderCommon.h"
#include "SnowShading.h"

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
    depth2d_array<float> auxiliary [[texture(TextureIndexAuxiliaryShadowMap)]],
    depth2d_array<float> pointShadowMap [[texture(TextureIndexPointShadowMap)]],
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
    float4 baseTexel = baseMap.sample(trilinear, in.texcoord);
    float3 albedo = baseTexel.rgb;
    float snowMask = baseTexel.a;
    float weights[TerrainConstantMaxLayers] = {in.weights0.x, in.weights0.y, in.weights0.z,
                                               in.weights0.w, in.weights1.x, in.weights1.y,
                                               in.weights1.z, in.weights1.w};
    bool normalMaps = draw.normalMapsEnabled != 0;
    float2 normalXY =
        normalMaps ? terrainNormalXY(baseNormalMap.sample(trilinear, in.texcoord)) : float2(0.0);
    uint count = min(draw.layerCount, uint(TerrainConstantMaxLayers));
    float snow = (draw.snowLayers >> uint(TerrainConstantMaxLayers)) & 1u;
    for (uint layer = 0; layer < count; ++layer) {
        float weight = saturate(weights[layer]);
        float4 layerTexel = layerMaps[layer].sample(trilinear, in.texcoord);
        albedo = mix(albedo, layerTexel.rgb, weight);
        snowMask = mix(snowMask, layerTexel.a, weight);
        snow = mix(snow, float((draw.snowLayers >> layer) & 1u), weight);
        if (normalMaps) {
            float4 texel = layerNormalMaps[layer].sample(trilinear, in.texcoord);
            normalXY = mix(normalXY, terrainNormalXY(texel), weight);
        }
    }
    float3 normal = normalMaps ? terrainShadingNormal(in, normalXY) : normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float shadow = sunShadowFactor(in.worldPosition, frame, shadowMap, auxiliary, shadowSampler);
    if (rayTracedShadows) {
        float traced = rayTracedSunShadow(in.worldPosition, normalize(in.normal), frame, rayScene);
        if (rayShadowView) {
            return float4(float3(traced), 1.0);
        }
        shadow = min(shadow, traced);
    }
    float3 illumination = frame.sunColor * lambert * shadow + baseAmbient(frame) +
                          directionalAmbient(normal, frame) +
                          pointLighting(
                              in.worldPosition, normal, pointLights, draw.pointLightCount,
                              pointShadowsAt(
                                  in.worldPosition, normalize(in.normal), pointLights,
                                  draw.pointLightCount, pointShadowMap, shadowSampler));
    float3 lit = albedo * linearVertexColour(in.color.rgb, frame) * illumination;
    if (snow > 0.0) {
        float3 toEye = normalize(frame.cameraPosition - in.worldPosition);
        float shine = snowRim(toEye, normalize(in.normal), normal);
        lit += (shine + snowSparkle(in.worldPosition, shadow, frame)) * snowMask * snow;
    }
    return float4(applyFog(lit, in.worldPosition, frame), snowCoverageAlpha(snowMask * snow));
}

// Water: WATR colors and shading over three scrolling noise layers: the record's noise
// normal maps, or sine waves with the same wind, tile size, and slope until they load
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

// The NAM2-NAM4 noise maps: each layer scrolls along its wind at its speed, in tiles of
// its UV scale, and its amplitude scales the slope of its tangent-space normal.
static float2 waterNoiseSlope(
    float2 xy,
    float time,
    constant WaterDrawUniforms &draw,
    texture2d<float> layer0,
    texture2d<float> layer1,
    texture2d<float> layer2,
    sampler trilinear)
{
    float2 flowing = xy - draw.flowVelocity * time;
    float2 slope = 0.0;
    for (int layer = 0; layer < 3; ++layer) {
        float tile = max(draw.uvScales[layer], 50.0);
        float angle = draw.windDirections[layer];
        float2 uv = flowing / tile + float2(cos(angle), sin(angle)) * draw.windSpeeds[layer] * time;
        float3 texel = layer == 0   ? layer0.sample(trilinear, uv).xyz
                       : layer == 1 ? layer1.sample(trilinear, uv).xyz
                                    : layer2.sample(trilinear, uv).xyz;
        slope += (texel.xy * 2.0 - 1.0) * draw.amplitudes[layer];
    }
    return slope;
}

// One exterior cell, in game units.
constant float waterCellSize = 4096.0;

// A river's flow normal (docs/rendering/water.md#flow-maps). Four flow-map texels, half a
// texel apart, each turn and scroll the flow noise; tent weights blend them, so no seam
// shows. `blend` is how much the result replaces the wind noise.
static float3 waterFlowNormal(
    float2 xy,
    float time,
    constant WaterDrawUniforms &draw,
    texture2d<float> flowMap,
    texture2d<float> flowNoise,
    sampler trilinear,
    thread float &blend)
{
    constexpr sampler texel(filter::nearest, address::clamp_to_edge);
    float2 local = (xy - draw.modelMatrix[3].xy) / waterCellSize;
    float2 uv = float2(local.x, 1.0 - local.y);
    float2 tent = 1.0 - abs(2.0 * fract(64.0 * uv) - 1.0);
    float halfStep = 1.0 / 128.0;
    float2 noiseBase = xy / (2.0 * waterCellSize) * 64.0 * sqrt(max(1.01 - draw.flow.y, 0.0));
    const float4 rates = float4(8.0, 8.48, 10.64, 9.92);
    const float4 offsets = float4(0.0, 0.62, 0.27, 0.0);
    const float2 steps[4] = {
        float2(0.0), float2(halfStep, 0.0), float2(0.0, halfStep), float2(halfStep)};
    float4 weights = float4(
        tent.x * tent.y, (1.0 - tent.x) * tent.y, tent.x * (1.0 - tent.y),
        (1.0 - tent.x) * (1.0 - tent.y));
    float2 slope = 0.0;
    blend = 0.0;
    for (int tap = 0; tap < 4; ++tap) {
        float4 flow = flowMap.sample(texel, uv + steps[tap], level(0.0));
        float2 direction = flow.xy * 2.0 - 1.0;
        float2 noiseUV = float2(
            direction.x * noiseBase.x - direction.y * noiseBase.y,
            direction.x * noiseBase.y + direction.y * noiseBase.x);
        noiseUV.x -= time * 0.001 * flow.a * rates[tap];
        noiseUV += offsets[tap];
        slope += (flowNoise.sample(trilinear, noiseUV).xy - 0.5) * weights[tap];
        blend += flow.z * weights[tap];
    }
    float2 spread = tent * tent + (1.0 - tent) * (1.0 - tent);
    slope /= max(sqrt(spread.x * spread.y), 1.0e-3);
    return float3(slope, sqrt(saturate(1.0 - dot(slope, slope))));
}

// One ring around a point: a wave crest that runs out at the displacement velocity, as
// wide as the starting size, fading with the dampener over its life and with distance.
static float2 waterRingSlope(float2 xy, float4 ring, constant WaterDrawUniforms &draw)
{
    float2 offset = xy - ring.xy;
    float distanceOut = length(offset);
    float width = max(draw.displacement.x, 4.0);
    float front = ring.z * max(draw.displacement.z, 8.0);
    float band = (distanceOut - front) / width;
    if (abs(band) > 3.0 || distanceOut < 0.001) {
        return 0.0;
    }
    float life = pow(saturate(draw.displacement.w), ring.z * 30.0) * saturate(1.0 - ring.z / 3.0);
    float spread = 1.0 / (1.0 + distanceOut * max(draw.rings.x, 0.0) * 0.01);
    float wave = cos(band * 3.1415927) * exp(-band * band);
    return offset / distanceOut * (wave * ring.w * max(draw.displacement.y, 0.2) * life * spread);
}

// Rain: a 48-unit grid, one drop per cell at a random place and time, each a short ring.
static float2 waterRainSlope(float2 xy, float time, float rain)
{
    if (rain <= 0.0) {
        return 0.0;
    }
    float2 slope = 0.0;
    float2 cell = floor(xy / 48.0);
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            float2 id = cell + float2(dx, dy);
            float3 random = fract(
                sin(float3(
                    dot(id, float2(127.1, 311.7)), dot(id, float2(269.5, 183.3)),
                    dot(id, float2(419.2, 371.9)))) *
                43758.5453);
            if (random.z > rain) {
                continue;
            }
            float age = fract(time * 1.25 + random.z * 7.0) * 0.8;
            float2 offset = xy - (id + random.xy) * 48.0;
            float distanceOut = length(offset);
            float band = (distanceOut - age * 30.0) / 3.0;
            if (abs(band) > 3.0 || distanceOut < 0.001) {
                continue;
            }
            float wave = cos(band * 3.1415927) * exp(-band * band) * (1.0 - age / 0.8);
            slope += offset / distanceOut * wave * 0.35;
        }
    }
    return slope;
}

// Screen-space reflection: the reflected ray steps through the scene drawn before the
// water, with steps that grow by a quarter each time. The first step behind a stored
// surface, and close to it, is the hit. rgb the colour, a its weight, which fades as in
// the game: by the hit's distance from the screen centre and by its length on screen.
static float4 waterScreenReflection(
    float3 origin,
    float3 direction,
    constant FrameUniforms &frame,
    constant WaterDrawUniforms &draw,
    depth2d<float> sceneDepth,
    texture2d<float> sceneColor)
{
    constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float stepLength = 24.0;
    float3 point = origin;
    float4 start = frame.viewProjectionMatrix * float4(origin, 1.0);
    float2 startUV = start.xy / max(start.w, 1.0e-4) * float2(0.5, -0.5) + 0.5;
    for (int step = 0; step < 24; ++step) {
        point += direction * stepLength;
        stepLength *= 1.25;
        float4 clip = frame.viewProjectionMatrix * float4(point, 1.0);
        if (clip.w <= 0.0) {
            break;
        }
        float3 ndc = clip.xyz / clip.w;
        float2 uv = ndc.xy * float2(0.5, -0.5) + 0.5;
        if (any(uv < 0.0) || any(uv > 1.0)) {
            break;
        }
        float stored = sceneDepth.sample(nearest, uv);
        if (stored >= 1.0 || ndc.z <= stored) {
            continue;
        }
        float pointDepth = draw.depthUnproject.y / (ndc.z + draw.depthUnproject.x);
        float surfaceDepth = draw.depthUnproject.y / (stored + draw.depthUnproject.x);
        if (pointDepth - surfaceDepth > stepLength * 2.0) {
            break;
        }
        float centre = min(2.0 * length(uv - 0.5), 1.0);
        float lengthFade = saturate(1.0 - length(uv - startUV));
        return float4(sceneColor.sample(linear, uv).rgb, (1.0 - centre * centre) * lengthFade);
    }
    return 0.0;
}

fragment float4 waterFragment(
    WaterVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant WaterDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    depth2d<float> sceneDepth [[texture(TextureIndexSceneDepth)]],
    texture2d<float> sceneColor [[texture(TextureIndexSceneColor)]],
    texture2d<float> noise0 [[texture(TextureIndexSurfaceNormal)]],
    texture2d<float> noise1 [[texture(TextureIndexSurfaceGlow)]],
    texture2d<float> noise2 [[texture(TextureIndexSurfaceDetail)]],
    texture2d<float> flowMap [[texture(TextureIndexWaterFlowMap)]],
    texture2d<float> flowNoise [[texture(TextureIndexWaterFlowNoise)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
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
    float time = frame.animationTime;
    float3 normal = waterNormal(in.worldPosition.xy, time, draw);
    if (draw.detail.w > 0.5) {
        float2 slope =
            waterNoiseSlope(in.worldPosition.xy, time, draw, noise0, noise1, noise2, trilinear);
        normal = normalize(float3(slope, 1.0));
    }
    float fade = 1.0;
    if (draw.amplitudes.w >= 0.0) {
        fade = saturate(1.0 - length(toCamera) / max(draw.amplitudes.w, 0.001));
        normal = normalize(float3(normal.xy / max(normal.z, 0.05) * fade, 1.0));
    }
    if (draw.flow.x > 0.5) {
        // The flow normal never fades below 0.4, so a far river still moves.
        float blend;
        float3 flowNormal =
            waterFlowNormal(in.worldPosition.xy, time, draw, flowMap, flowNoise, trilinear, blend);
        flowNormal.xy *= max(fade, 0.4);
        flowNormal.z = sqrt(saturate(1.0 - dot(flowNormal.xy, flowNormal.xy)));
        normal = normalize(normal + saturate(blend) * (flowNormal - normal));
    }
    float2 ringSlope = waterRainSlope(in.worldPosition.xy, time, draw.rings.y);
    uint ringCount = min(uint(draw.rings.z), uint(WaterConstantMaxRipples));
    for (uint ring = 0; ring < ringCount; ++ring) {
        ringSlope += waterRingSlope(in.worldPosition.xy, draw.ripples[ring], draw);
    }
    normal = normalize(float3(normal.xy / max(normal.z, 0.05) + ringSlope, 1.0));
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
    float3 mirrored = reflect(-view, normal);
    if (frame.screenSpaceReflections != 0 && draw.depthAndSun.w > 0.5) {
        float4 hit =
            waterScreenReflection(in.worldPosition, mirrored, frame, draw, sceneDepth, sceneColor);
        sky = mix(sky, hit.rgb, hit.a);
    }
    float3 color = mix(body * (frame.ambientColor + frame.sunColor * 0.6), sky, reflection);

    float sunAlign = saturate(dot(mirrored, -frame.sunDirection));
    float specular = pow(sunAlign, max(draw.surface.w * 0.25, 8.0)) * draw.depthAndSun.x;
    // Sparkle: the sharp glints of the same normal, by the sparkle power and magnitude.
    float sparkle =
        draw.detail.y > 0.0 ? pow(sunAlign, max(draw.detail.z, 1.0)) * draw.detail.y : 0.0;
    color += frame.sunColor * (specular + sparkle);

    // Shallow water shows the ground through it; deep or edge-on water hides it.
    float seeThrough = 1.0 - smoothstep(0.0, max(draw.depthAndSun.z, 1.0) * 2.0, rayDepth);
    float bodyAlpha = mix(1.0, draw.surface.x, seeThrough);
    float alpha = saturate(max(bodyAlpha, reflection) + specular + sparkle);
    if (draw.rings.w > 0.5) {
        // Refraction: the ground under the surface, bent by the normal. A bent sample
        // that lands on something in front of the water keeps the straight one.
        float2 screen = in.position.xy / float2(sceneColor.get_width(), sceneColor.get_height());
        float bend = draw.detail.x * saturate(rayDepth / max(draw.depthAndSun.z, 1.0));
        float2 bent = clamp(screen + normal.xy * bend, 0.0, 1.0);
        constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
        constexpr sampler nearestClamp(filter::nearest, address::clamp_to_edge);
        float stored = sceneDepth.sample(nearestClamp, bent);
        float bentDepth = draw.depthUnproject.y / (stored + draw.depthUnproject.x);
        float surfaceDepth = dot(-toCamera, frame.cameraForward);
        float2 under = bentDepth > surfaceDepth ? bent : screen;
        float3 ground = sceneColor.sample(linearClamp, under).rgb;
        return float4(mix(ground, applyFog(color, in.worldPosition, frame), alpha), 1.0);
    }
    return float4(applyFog(color, in.worldPosition, frame), alpha);
}
