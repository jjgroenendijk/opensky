#include "EffectShading.h"

// The sun, its glare, the moons, the stars, and the aurora. They follow the camera
// and draw after the sky gradient, before the cloud layers, with no depth test.
// Output is premultiplied: an additive object writes alpha 0.

typedef struct
{
    float4 position [[position]];
    float4 color;
    float2 texcoord;
    float3 normal;
    float3 toEye;
} SkyObjectVertexOut;

static float4 skyObjectClip(float3 offset, constant FrameUniforms &frame)
{
    float4 clip = frame.viewProjectionMatrix * float4(frame.cameraPosition + offset, 1.0);
    // Any depth inside the clip range: these draw with no depth test.
    clip.z = clip.w * 0.5;
    return clip;
}

vertex SkyObjectVertexOut skyMeshVertex(
    uint vertexID [[vertex_id]],
    const device CloudVertex *vertices [[buffer(BufferIndexVertices)]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant SkyObjectUniforms &object [[buffer(BufferIndexDrawUniforms)]])
{
    CloudVertex source = vertices[vertexID];
    float3 offset = (object.rotation * float4(source.position.xyz, 0.0)).xyz;
    SkyObjectVertexOut out;
    out.position = skyObjectClip(offset, frame);
    out.color = source.color;
    out.texcoord = source.texcoord;
    out.normal = (object.rotation * float4(source.normal.xyz, 0.0)).xyz;
    out.toEye = -offset;
    return out;
}

// A camera-facing card: six corners from vertex_id, a hundred units out.
vertex SkyObjectVertexOut skyCardVertex(
    uint vertexID [[vertex_id]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]],
    constant SkyObjectUniforms &object [[buffer(BufferIndexDrawUniforms)]])
{
    const float2 corners[6] = {float2(-1.0, -1.0), float2(1.0, -1.0), float2(1.0, 1.0),
                               float2(-1.0, -1.0), float2(1.0, 1.0),  float2(-1.0, 1.0)};
    float2 corner = corners[vertexID];
    float3 offset = object.center.xyz +
                    (object.right.xyz * corner.x + object.up.xyz * corner.y) * object.center.w;
    SkyObjectVertexOut out;
    out.position = skyObjectClip(offset * 100.0, frame);
    out.color = float4(1.0);
    out.texcoord = float2(corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5);
    out.normal = -object.center.xyz;
    out.toEye = -object.center.xyz;
    return out;
}

fragment float4 skyObjectFragment(
    SkyObjectVertexOut in [[stage_in]],
    constant SkyObjectUniforms &object [[buffer(BufferIndexDrawUniforms)]],
    texture2d<float> map [[texture(TextureIndexDiffuse)]],
    texture2d<float> palette [[texture(TextureIndexEffectPalette)]],
    sampler trilinear [[sampler(SamplerIndexTrilinear)]])
{
    float4 texel = map.sample(trilinear, in.texcoord);
    float4 shaded = texel;
    if (object.effectFlags != 0) {
        EffectTerms terms;
        terms.flags = object.effectFlags;
        terms.falloff = object.falloff;
        terms.baseColor = object.baseColor;
        terms.baseColorScale = object.baseColorScale;
        shaded =
            effectShade(texel, in.color, normalize(in.normal), normalize(in.toEye), terms, palette);
    }
    if ((object.flags & SkyObjectFlagAlphaOnly) != 0) {
        shaded.rgb = float3(1.0);
    }
    float3 rgb = shaded.rgb * object.color.rgb;
    float alpha = saturate(shaded.a * object.color.a);
    bool additive = (object.flags & SkyObjectFlagAdditive) != 0;
    return float4(rgb * alpha, additive ? 0.0 : alpha);
}
