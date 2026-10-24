#include "ShaderCommon.h"
#include "SurfaceShading.h"
#include "EffectShading.h"

// Static-mesh path: diffuse * (directional sun + ambient),
// vertex color as tint (Skyrim bakes AO there). Alpha-test pipeline variant
// selected via function constant so opaque draws pay nothing for it.

constant bool alphaTestEnabled [[function_constant(FunctionConstantAlphaTest)]];
// Optional: only the blended static pipeline defines it. The others write alpha 1.
constant bool alphaBlendValue [[function_constant(FunctionConstantAlphaBlend)]];
constant bool alphaBlendEnabled = is_function_constant_defined(alphaBlendValue) && alphaBlendValue;

// Shader type 18 tiles textures/terrain/noise.dds once per cell. Its mean is 0.215, so
// dividing by it keeps the average colour of the land.
constant float landscapeNoiseTile = 1.0 / 4096.0;
constant float landscapeNoiseMean = 0.215;
// Inverse of the Creation Kit's terrain LOD brightening `gain * source^exponent` in gamma.
static inline float3 undoTerrainLODBrightening(float3 albedo, float2 curve)
{
    return toLinear(pow(toGamma(albedo) / curve.x, 1.0 / curve.y));
}
// Refraction strength 1 moves the scene by a tenth of the screen; fire refraction
// scrolls its normal map half a texture per second. Both are OpenSky choices.
constant float refractionReach = 0.1;
constant float fireRefractionScroll = 0.5;

// Instanced: matrices come from the per-instance transform
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
    out.instanceColor = instance.instanceColor;
    setBasis(out, upper3x3(instance.normalMatrix));
    return out;
}

// Bind-pose hardware skinning. Bone matrices use Gamebryo's documented
// rootParentToSkin * currentBoneToRootParent * skinToBoneBind composition;
// animation will replace this immutable per-mesh buffer in milestone 6.
vertex StaticVertexOut skinnedMeshVertex(
    SkinnedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant DrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device matrix_float4x4 *bones [[buffer(BufferIndexBoneMatrices)]])
{
    float4 skinPosition = 0.0;
    float3 skinNormal = 0.0;
    float3x3 skinBasis = float3x3(0.0);
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        matrix_float4x4 bone = bones[in.boneIndices[influence]];
        skinPosition += weight * (bone * float4(in.position, 1.0));
        skinNormal += weight * (bone * float4(in.normal, 0.0)).xyz;
        skinBasis = skinBasis + upper3x3(bone) * weight;
    }
    const device InstanceTransform &instance = instances[instanceID];
    float4 world = instance.modelMatrix * skinPosition;
    StaticVertexOut out;
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (instance.normalMatrix * float4(skinNormal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    out.color = in.color;
    out.instanceColor = instance.instanceColor;
    setBasis(out, upper3x3(instance.normalMatrix) * skinBasis);
    return out;
}

vertex StaticVertexOut morphedSkinnedMeshVertex(
    MorphedSkinnedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant DrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device matrix_float4x4 *bones [[buffer(BufferIndexBoneMatrices)]])
{
    float4 skinPosition = 0.0;
    float3 skinNormal = 0.0;
    float3x3 skinBasis = float3x3(0.0);
    float3 position = in.position + in.morphPositionDelta;
    float3 normal = in.normal + in.morphNormalDelta;
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        matrix_float4x4 bone = bones[in.boneIndices[influence]];
        skinPosition += weight * (bone * float4(position, 1.0));
        skinNormal += weight * (bone * float4(normal, 0.0)).xyz;
        skinBasis = skinBasis + upper3x3(bone) * weight;
    }
    const device InstanceTransform &instance = instances[instanceID];
    float4 world = instance.modelMatrix * skinPosition;
    StaticVertexOut out;
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (instance.normalMatrix * float4(skinNormal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    out.color = in.color;
    out.instanceColor = instance.instanceColor;
    setBasis(out, upper3x3(instance.normalMatrix) * skinBasis);
    return out;
}

struct SurfaceMaps
{
    texture2d<float> normal;
    texture2d<float> glow;
    texture2d<float> detail;
    texturecube<float> environment;
    texture2d<float> environmentMask;
    texture2d<float> layer;
    texture2d<float> backLight;
};

// The surface normal and the specular and reflection mask from the normal map.
struct SurfaceNormal
{
    float3 world;
    float3 tangentSpace;
    float mask;
};

static SurfaceNormal surfaceNormal(
    StaticVertexOut in, float3x3 frame, float2 uv, uint terms, SurfaceMaps maps, sampler trilinear)
{
    SurfaceNormal result = {frame[2], float3(0, 0, 1), 1.0};
    if (!hasTerm(terms, ShadingTermNormalMap)) {
        return result;
    }
    float4 texel = maps.normal.sample(trilinear, uv);
    result.mask = texel.a;
    if (hasTerm(terms, ShadingTermModelSpaceNormals)) {
        // Model-space maps store x, z, y in r, g, b (NifSkope sk_msn, confirmed on
        // the real head maps). The basis carries them to world space.
        float3x3 basis = float3x3(in.basisX, in.basisY, in.basisZ);
        result.world = normalize(basis * (texel.rbg * 2.0 - 1.0));
        return result;
    }
    result.tangentSpace = normalize(texel.rgb * 2.0 - 1.0);
    result.world = normalize(frame * result.tangentSpace);
    return result;
}

// FaceGen: the detail map and the face tint overlay the albedo, then it doubles.
static float3 faceAlbedo(float3 albedo, float2 uv, uint terms, SurfaceMaps maps, sampler trilinear)
{
    bool detail = hasTerm(terms, ShadingTermFaceDetail);
    bool tint = hasTerm(terms, ShadingTermFaceTint);
    if (!detail && !tint) {
        return albedo;
    }
    float3 gamma = toGamma(albedo);
    if (detail) {
        gamma = overlayGamma(gamma, toGamma(maps.detail.sample(trilinear, uv).rgb));
    }
    if (tint) {
        gamma = overlayGamma(gamma, toGamma(maps.layer.sample(trilinear, uv).rgb));
    }
    return toLinear(detail ? gamma * 2.0 : gamma);
}

static float3 reflection(
    float3 normal,
    float3 toEye,
    float mask,
    float2 uv,
    uint terms,
    constant DrawUniforms &draw,
    SurfaceMaps maps,
    sampler trilinear)
{
    if (!hasTerm(terms, ShadingTermEnvironment)) {
        return 0.0;
    }
    float3 cube = maps.environment.sample(trilinear, cubeDirection(reflect(-toEye, normal))).rgb;
    if (hasTerm(terms, ShadingTermEnvironmentMask)) {
        mask = maps.environmentMask.sample(trilinear, uv).r;
    }
    return cube * draw.lightingEffects.z * mask;
}

struct LitInput
{
    float3 albedo;
    float3 toEye;
    float3 strand;
    float2 uv;
    float shadow;
    uint terms;
};

// The emissive colour, or the reference's emittance on an external-emittance shape.
static float3 emittedLight(
    StaticVertexOut in,
    LitInput input,
    constant DrawUniforms &draw,
    SurfaceMaps maps,
    sampler trilinear)
{
    uint terms = input.terms;
    bool external = hasTerm(terms, ShadingTermExternalEmittance) && in.instanceColor.a > 0.0;
    if (!hasTerm(terms, ShadingTermEmissive) && !external) {
        return 0.0;
    }
    float3 emitted = (external ? in.instanceColor.rgb : draw.emissive.rgb) * draw.emissive.a;
    if (hasTerm(terms, ShadingTermGlowMap)) {
        emitted *= maps.glow.sample(trilinear, input.uv).rgb;
    }
    return emitted;
}

static float3 litSurface(
    StaticVertexOut in,
    LitInput input,
    SurfaceNormal normal,
    constant FrameUniforms &frame,
    constant DrawUniforms &draw,
    const device PointLightUniform *pointLights,
    SurfaceMaps maps,
    sampler trilinear)
{
    uint terms = input.terms;
    LightGeometry geometry = {normal.world,           input.toEye,
                              input.strand,           max(draw.specular.a, 1.0),
                              draw.lightingEffects.x, draw.lightingEffects.y};
    LightSums sums = {0.0, 0.0, 0.0, 0.0, 0.0};
    addLight(sums, geometry, -frame.sunDirection, frame.sunColor * input.shadow, terms);
    addPointLights(sums, geometry, in.worldPosition, pointLights, draw.pointLightCount, terms);
    if (hasTerm(terms, ShadingTermHairSoftLighting)) {
        // nif.xml: keeps hair from going too bright under lights.
        sums.diffuse = min(sums.diffuse, 1.0);
    }
    float3 ambient = directionalAmbient(normal.world, frame) + baseAmbient(frame);
    float3 emitted = emittedLight(in, input, draw, maps, trilinear);
    float3 lightMask = maps.glow.sample(trilinear, input.uv).rgb;
    float3 back = 0.0;
    if (hasTerm(terms, ShadingTermBackLighting)) {
        back = sums.back * maps.backLight.sample(trilinear, input.uv).rgb;
    }
    float3 illumination =
        sums.diffuse + ambient + emitted + back + (sums.rim + sums.soft) * lightMask;
    float3 specular = 0.0;
    if (hasTerm(terms, ShadingTermSpecular)) {
        float mask = normal.mask;
        if (hasTerm(terms, ShadingTermSpecularMap)) {
            mask = maps.backLight.sample(trilinear, input.uv).r;
        }
        specular = draw.specular.rgb * mask * sums.specular;
    }
    if (hasTerm(terms, ShadingTermSparkle)) {
        float glint = sparkle(input.uv, geometry, -frame.sunDirection, draw.multiLayer);
        specular += frame.sunColor * input.shadow * glint;
    }
    return input.albedo * illumination + specular;
}

struct RefractionInput
{
    float2 pixel;
    float2 uv;
    float fade;
    uint terms;
};

// The scene copy, bent by the normal map. Fire refraction scrolls the map upward, and
// the vertex and material alpha fade the bend out toward the shape's edges.
static float3 refracted(
    RefractionInput input,
    constant FrameUniforms &frame,
    constant DrawUniforms &draw,
    texture2d<float> normalMap,
    texture2d<float> scene,
    sampler trilinear)
{
    float2 uv = input.uv;
    if (hasTerm(input.terms, ShadingTermFireRefraction)) {
        uv.y += frame.animationTime * fireRefractionScroll;
    }
    float2 bend = normalMap.sample(trilinear, uv).xy * 2.0 - 1.0;
    float2 size = float2(scene.get_width(), scene.get_height());
    float reach = draw.lightingEffects.w * refractionReach * saturate(input.fade);
    constexpr sampler clamped(filter::linear, address::clamp_to_edge);
    return scene.sample(clamped, input.pixel / size + bend * reach).rgb;
}

// The additive pipelines add the colour as it is, so the shader applies the source
// factor. Opaque: alpha only gates the test. The frame is premultiplied, so a lower
// alpha would show as white or black. The blended pass blends it.
static inline float4 blendOutput(
    float3 colour,
    float alpha,
    float3 worldPosition,
    constant FrameUniforms &frame,
    constant DrawUniforms &draw)
{
    if (draw.additiveBlend != 0) {
        float3 added = applyAdditiveFog(colour, worldPosition, frame);
        return float4(draw.additiveBlend == 1 ? added * alpha : added, alpha);
    }
    return float4(applyFog(colour, worldPosition, frame), alphaBlendEnabled ? alpha : 1.0);
}

fragment float4 staticMeshFragment(
    StaticVertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant DrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device PointLightUniform *pointLights [[buffer(BufferIndexPointLights)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    texture2d<float> effectPalette [[texture(TextureIndexEffectPalette)]],
    texture2d<float> normalMap [[texture(TextureIndexSurfaceNormal)]],
    texture2d<float> glowMap [[texture(TextureIndexSurfaceGlow)]],
    texture2d<float> detailMap [[texture(TextureIndexSurfaceDetail)]],
    texturecube<float> environmentMap [[texture(TextureIndexSurfaceEnvironment)]],
    texture2d<float> environmentMask [[texture(TextureIndexSurfaceEnvironmentMask)]],
    texture2d<float> layerMap [[texture(TextureIndexSurfaceLayer)]],
    texture2d<float> backLightMap [[texture(TextureIndexSurfaceBackLight)]],
    texture2d<float> sceneColour [[texture(TextureIndexSceneColor)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    depth2d<float> sceneDepth [[texture(TextureIndexSceneDepth)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]],
    raytracing::instance_acceleration_structure rayScene
    [[buffer(BufferIndexRayScene), function_constant(rayTracedShadows)]])
{
    SurfaceMaps maps = {normalMap,       glowMap,  detailMap,   environmentMap,
                        environmentMask, layerMap, backLightMap};
    uint terms = draw.materialFlags & frame.shadingTerms;
    float3 toEye = normalize(frame.cameraPosition - in.worldPosition);
    // Derivatives first: they need every pixel of the quad, before any discard.
    float3x3 tangentFrame = cotangentFrame(normalize(in.normal), in.worldPosition, in.texcoord);
    float3 toEyeTangent = toEye * tangentFrame;
    float2 uv = in.texcoord;
    if (hasTerm(terms, ShadingTermParallax)) {
        float height = detailMap.sample(trilinear, uv).r;
        uv += toEyeTangent.xy * (height * 0.08 - 0.04);
    }
    float4 diffuse = diffuseMap.sample(trilinear, uv);
    bool isEffect = (draw.effectFlags & EffectFlagEnabled) != 0;
    float4 effect = 0.0;
    float alpha = diffuse.a * in.color.a * draw.materialAlpha;
    if (isEffect) {
        effect = effectShade(
            diffuse, in.color, normalize(in.normal), toEye,
            EffectTerms{
                draw.effectFlags, draw.effectFalloff, draw.effectBaseColor,
                draw.effectBaseColorScale},
            effectPalette);
        alpha = effect.a * draw.materialAlpha;
        if ((draw.effectFlags & EffectFlagSoft) != 0) {
            alpha *= softEffectFade(
                in.position.xy, in.worldPosition, draw.effectSoftDepth, frame, sceneDepth);
        }
    }
    if (alphaTestEnabled && alpha < draw.alphaThreshold) {
        discard_fragment();
    }
    if (hasTerm(terms, ShadingTermScreenDoor)) {
        if (alpha < screenDoorThreshold(in.position.xy)) {
            discard_fragment();
        }
        alpha = 1.0;
    }
    if (debugViewActive) {
        DebugSurface surface = {
            in.worldPosition, in.normal, in.texcoord,
            diffuseMap.calculate_unclamped_lod(trilinear, in.texcoord), draw.layerCategory};
        return debugViewColor(frame, surface);
    }
    if (hasTerm(terms, ShadingTermRefraction)) {
        RefractionInput refraction = {in.position.xy, uv, alpha, terms};
        return float4(refracted(refraction, frame, draw, normalMap, sceneColour, trilinear), 1.0);
    }
    if (isEffect) {
        EffectLightInput light = {draw.effectFlags,
                                  draw.effectLightingInfluence,
                                  in.worldPosition,
                                  normalize(in.normal),
                                  toEye,
                                  in.instanceColor};
        float3 lit = effect.rgb * effectLight(light, frame, pointLights, draw.pointLightCount);
        return blendOutput(lit, alpha, in.worldPosition, frame, draw);
    }
    SurfaceNormal normal = surfaceNormal(in, tangentFrame, uv, terms, maps, trilinear);
    float shadow = draw.receivesShadows != 0
                       ? sunShadowFactor(in.worldPosition, frame, shadowMap, shadowSampler)
                       : 1.0;
    if (rayTracedShadows) {
        float traced =
            draw.receivesShadows != 0
                ? rayTracedSunShadow(in.worldPosition, normalize(in.normal), frame, rayScene)
                : 1.0;
        if (rayShadowView) {
            return float4(float3(traced), 1.0);
        }
        shadow = min(shadow, traced);
    }
    float3 vertexColour = linearVertexColour(in.color.rgb, frame);
    float3 albedo = diffuse.rgb * vertexColour;
    if (hasTerm(terms, ShadingTermLandscapeNoise)) {
        float noise = detailMap.sample(trilinear, in.worldPosition.xy * landscapeNoiseTile).r;
        albedo *= mix(1.0, noise / landscapeNoiseMean, 0.5);
        albedo = undoTerrainLODBrightening(albedo, frame.terrainLODBrightening);
    }
    if (hasTerm(terms, ShadingTermMultiLayer)) {
        float innerAlpha = layerMap.sample(trilinear, uv).a;
        float2 inner =
            innerLayerCoordinate(uv, toEyeTangent, normal.tangentSpace, draw, innerAlpha);
        float3 innerColour = layerMap.sample(trilinear, inner).rgb * vertexColour;
        float outerMix = max(1.0 - max(dot(normal.world, toEye), 0.0), diffuse.a);
        albedo = mix(innerColour, albedo, outerMix);
    }
    albedo = faceAlbedo(albedo, uv, terms, maps, trilinear);
    float3 reflected =
        reflection(normal.world, toEye, normal.mask, uv, terms, draw, maps, trilinear);
    bool reflectionLit = hasTerm(terms, ShadingTermEnvironmentLightFade);
    albedo += reflectionLit ? reflected : 0.0;
    if (hasTerm(terms, ShadingTermSkinTint)) {
        albedo = toLinear(overlayGamma(toGamma(albedo), draw.tintColor.rgb));
    } else if (hasTerm(terms, ShadingTermTintColor)) {
        albedo *= linearVertexColour(draw.tintColor.rgb, frame);
    }
    LitInput input = {albedo, toEye, tangentFrame[1], uv, shadow, terms};
    float3 lit = litSurface(in, input, normal, frame, draw, pointLights, maps, trilinear);
    lit += reflectionLit ? 0.0 : reflected;
    return blendOutput(lit, alpha, in.worldPosition, frame, draw);
}

// Sun-shadow depth pre-pass: each caster renders into one cascade slice,
// depth only. Static and skinned casters take their model matrix from the
// instance/bone path, terrain from ShadowDrawUniforms.modelMatrix. Only the
// alpha-test variant has a fragment, for the diffuse alpha discard.

typedef struct
{
    float4 position [[position]];
    float2 texcoord;
} ShadowVertexOut;

vertex ShadowVertexOut shadowStaticVertex(
    StaticVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant ShadowDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]])
{
    ShadowVertexOut out;
    float4 world = instances[instanceID].modelMatrix * float4(in.position, 1.0);
    out.position = draw.lightViewProjection * world;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    return out;
}

vertex ShadowVertexOut shadowSkinnedVertex(
    SkinnedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant ShadowDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device matrix_float4x4 *bones [[buffer(BufferIndexBoneMatrices)]])
{
    float4 skinPosition = 0.0;
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        skinPosition += weight * (bones[in.boneIndices[influence]] * float4(in.position, 1.0));
    }
    ShadowVertexOut out;
    float4 world = instances[instanceID].modelMatrix * skinPosition;
    out.position = draw.lightViewProjection * world;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    return out;
}

vertex ShadowVertexOut shadowMorphedSkinnedVertex(
    MorphedSkinnedVertexIn in [[stage_in]],
    uint instanceID [[instance_id]],
    constant ShadowDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    const device InstanceTransform *instances [[buffer(BufferIndexInstanceTransforms)]],
    const device matrix_float4x4 *bones [[buffer(BufferIndexBoneMatrices)]])
{
    float4 skinPosition = 0.0;
    float3 position = in.position + in.morphPositionDelta;
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        skinPosition += weight * (bones[in.boneIndices[influence]] * float4(position, 1.0));
    }
    ShadowVertexOut out;
    float4 world = instances[instanceID].modelMatrix * skinPosition;
    out.position = draw.lightViewProjection * world;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    return out;
}

vertex ShadowVertexOut shadowTerrainVertex(
    StaticVertexIn in [[stage_in]],
    constant ShadowDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]])
{
    ShadowVertexOut out;
    float4 world = draw.modelMatrix * float4(in.position, 1.0);
    out.position = draw.lightViewProjection * world;
    out.texcoord = in.texcoord;
    return out;
}

fragment void shadowAlphaTestFragment(
    ShadowVertexOut in [[stage_in]],
    constant ShadowDrawUniforms &draw [[buffer(BufferIndexDrawUniforms)]],
    texture2d<float> diffuseMap [[texture(TextureIndexDiffuse)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    float alpha = diffuseMap.sample(trilinear, in.texcoord).a;
    if (alpha < draw.alphaThreshold) {
        discard_fragment();
    }
}
