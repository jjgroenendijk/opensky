#include "ShaderCommon.h"
#include "EffectShading.h"

// The menu scene (docs/rendering/menu-scene.md): unlit effect meshes with their own
// camera, drawn in place of the world, such as the perk sky.

typedef struct
{
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 texcoord;
    float4 color;
} MenuSceneVertexOut;

vertex MenuSceneVertexOut menuSceneVertex(
    uint vertexID [[vertex_id]],
    const device MenuSceneVertex *vertices [[buffer(BufferIndexMenuSceneVertices)]],
    constant MenuSceneUniforms &draw [[buffer(BufferIndexMenuSceneUniforms)]])
{
    const device MenuSceneVertex &in = vertices[vertexID];
    MenuSceneVertexOut out;
    out.position = draw.modelViewProjection * float4(in.position.xyz, 1.0);
    out.worldPosition = (draw.model * float4(in.position.xyz, 1.0)).xyz;
    out.normal = (draw.model * float4(in.normal.xyz, 0.0)).xyz;
    out.texcoord = in.uv * draw.uvTransform.zw + draw.uvTransform.xy;
    out.color = in.color;
    return out;
}

fragment float4 menuSceneFragment(
    MenuSceneVertexOut in [[stage_in]],
    constant MenuSceneUniforms &draw [[buffer(BufferIndexMenuSceneUniforms)]],
    texture2d<float> sourceMap [[texture(TextureIndexDiffuse)]],
    texture2d<float> palette [[texture(TextureIndexEffectPalette)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    float4 base = draw.hasTexture != 0 ? sourceMap.sample(trilinear, in.texcoord) : float4(1.0);
    float3 toEye = normalize(draw.cameraPosition.xyz - in.worldPosition);
    float3 normal = length_squared(in.normal) > 0.0 ? normalize(in.normal) : toEye;
    float4 shaded = effectShade(
        base, in.color, normal, toEye,
        EffectTerms{
            draw.effectFlags, draw.effectFalloff, draw.effectBaseColor, draw.effectBaseColorScale},
        palette);
    if (draw.cameraPosition.w > 0.0 && shaded.a <= draw.cameraPosition.w) {
        discard_fragment();
    }
    return draw.isOpaque != 0 ? float4(shaded.rgb, 1.0) : shaded;
}
