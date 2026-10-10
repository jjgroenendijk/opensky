#include "ShaderCommon.h"

// Static-mesh path: diffuse * (directional sun + ambient),
// vertex color as tint (Skyrim bakes AO there). Alpha-test pipeline variant
// selected via function constant so opaque draws pay nothing for it.

constant bool alphaTestEnabled [[function_constant(FunctionConstantAlphaTest)]];
// Optional: only the blended static pipeline defines it. The others write alpha 1.
constant bool alphaBlendValue [[function_constant(FunctionConstantAlphaBlend)]];
constant bool alphaBlendEnabled = is_function_constant_defined(alphaBlendValue) && alphaBlendValue;

// BSEffectShaderProperty shading: unlit, base color, palette, and falloff. The
// model follows NifSkope's open-source effect shader (sk_effectshader.frag).
static float4 effectShade(
    float4 base,
    float4 vertexColor,
    float3 normal,
    float3 toEye,
    constant DrawUniforms &draw,
    texture2d<float> palette)
{
    constexpr sampler paletteSampler(filter::linear, address::clamp_to_edge);
    uint flags = draw.effectFlags;
    float4 tint = (flags & EffectFlagVertexColors) != 0 ? vertexColor : float4(1.0);
    tint.a = (flags & EffectFlagVertexAlpha) != 0 ? vertexColor.a : 1.0;
    float falloff = 1.0;
    if ((flags & EffectFlagFalloff) != 0) {
        float4 range = draw.effectFalloff;
        float facing = smoothstep(range.y, range.x, abs(dot(normal, toEye)));
        falloff = mix(max(range.w, 0.0), min(range.z, 1.0), facing);
    }
    float4 glow = draw.effectBaseColor;
    float alphaScale = glow.a * glow.a;
    float3 rgb = base.rgb * tint.rgb * glow.rgb;
    float alpha = base.a * tint.a * falloff * alphaScale;
    if ((flags & EffectFlagPaletteColor) != 0) {
        float2 at = saturate(float2(base.g, tint.g * falloff * glow.r));
        rgb = palette.sample(paletteSampler, at).rgb;
    }
    if ((flags & EffectFlagPaletteAlpha) != 0) {
        float2 at = saturate(float2(base.a, tint.a * falloff * alphaScale));
        alpha = palette.sample(paletteSampler, at).a;
    }
    return float4(rgb * draw.effectBaseColorScale, alpha);
}

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
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        matrix_float4x4 bone = bones[in.boneIndices[influence]];
        skinPosition += weight * (bone * float4(in.position, 1.0));
        skinNormal += weight * (bone * float4(in.normal, 0.0)).xyz;
    }
    const device InstanceTransform &instance = instances[instanceID];
    float4 world = instance.modelMatrix * skinPosition;
    StaticVertexOut out;
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (instance.normalMatrix * float4(skinNormal, 0.0)).xyz;
    out.worldPosition = world.xyz;
    out.texcoord = in.texcoord * draw.uvScale + draw.uvOffset;
    out.color = in.color;
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
    float3 position = in.position + in.morphPositionDelta;
    float3 normal = in.normal + in.morphNormalDelta;
    for (uint influence = 0; influence < 4; ++influence) {
        float weight = in.boneWeights[influence];
        matrix_float4x4 bone = bones[in.boneIndices[influence]];
        skinPosition += weight * (bone * float4(position, 1.0));
        skinNormal += weight * (bone * float4(normal, 0.0)).xyz;
    }
    const device InstanceTransform &instance = instances[instanceID];
    float4 world = instance.modelMatrix * skinPosition;
    StaticVertexOut out;
    out.position = frame.viewProjectionMatrix * world;
    out.normal = (instance.normalMatrix * float4(skinNormal, 0.0)).xyz;
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
    texture2d<float> effectPalette [[texture(TextureIndexEffectPalette)]],
    depth2d_array<float> shadowMap [[texture(TextureIndexShadowMap)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]],
    sampler shadowSampler [[sampler(SamplerIndexShadowCompare)]],
    raytracing::instance_acceleration_structure rayScene
    [[buffer(BufferIndexRayScene), function_constant(rayTracedShadows)]])
{
    float4 diffuse = diffuseMap.sample(trilinear, in.texcoord);
    bool isEffect = (draw.effectFlags & EffectFlagEnabled) != 0;
    float4 effect = 0.0;
    float alpha = diffuse.a * in.color.a * draw.materialAlpha;
    if (isEffect) {
        float3 toEye = normalize(frame.cameraPosition - in.worldPosition);
        effect = effectShade(diffuse, in.color, normalize(in.normal), toEye, draw, effectPalette);
        alpha = effect.a * draw.materialAlpha;
    }
    if (alphaTestEnabled && alpha < draw.alphaThreshold) {
        discard_fragment();
    }
    if (debugViewActive) {
        DebugSurface surface = {
            in.worldPosition, in.normal, in.texcoord,
            diffuseMap.calculate_unclamped_lod(trilinear, in.texcoord), draw.layerCategory};
        return debugViewColor(frame, surface);
    }
    if (isEffect) {
        float3 shaded = applyFog(effect.rgb, in.worldPosition, frame);
        return float4(shaded, alphaBlendEnabled ? alpha : 1.0);
    }
    float3 normal = normalize(in.normal);
    float lambert = saturate(dot(normal, -frame.sunDirection));
    float shadow = draw.receivesShadows != 0
                       ? sunShadowFactor(in.worldPosition, frame, shadowMap, shadowSampler)
                       : 1.0;
    if (rayTracedShadows) {
        float traced = draw.receivesShadows != 0
                           ? rayTracedSunShadow(in.worldPosition, normal, frame, rayScene)
                           : 1.0;
        if (rayShadowView) {
            return float4(float3(traced), 1.0);
        }
        shadow = min(shadow, traced);
    }
    float3 illumination =
        frame.sunColor * lambert * shadow + frame.ambientColor + directionalAmbient(normal, frame) +
        pointLighting(in.worldPosition, normal, pointLights, draw.pointLightCount);
    float3 lit = diffuse.rgb * in.color.rgb * illumination;
    // Opaque: alpha only gates the test above. The frame is premultiplied, so
    // a lower alpha would show as white or black. The blended pass blends it.
    return float4(applyFog(lit, in.worldPosition, frame), alphaBlendEnabled ? alpha : 1.0);
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
