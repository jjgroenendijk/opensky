#include "ShaderCommon.h"

// Screen blood, drawn over the world and under the menus and the UI
// (docs/rendering/visual-effects.md#blood). The CPU builds the quads in clip
// space, so the vertex stage only passes them on. color.rgb is a tint and
// color.a the opacity; the output is premultiplied for the over blend.

typedef struct
{
    float4 position [[position]];
    float2 uv;
    float4 color;
} ScreenBloodVertexOut;

vertex ScreenBloodVertexOut screenBloodVertex(
    uint vertexID [[vertex_id]], const device UIVertex *vertices [[buffer(BufferIndexUIVertices)]])
{
    const device UIVertex &in = vertices[vertexID];
    ScreenBloodVertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    out.color = in.color;
    return out;
}

// The colour texture holds the blood, the mask texture its shape in alpha.
fragment float4 screenBloodFragment(
    ScreenBloodVertexOut in [[stage_in]],
    texture2d<float> color [[texture(TextureIndexScreenBloodColor)]],
    texture2d<float> mask [[texture(TextureIndexScreenBloodAlpha)]],
    sampler linearSampler [[sampler(SamplerIndexTrilinear)]])
{
    float3 rgb = color.sample(linearSampler, in.uv).rgb * in.color.rgb;
    float alpha = saturate(mask.sample(linearSampler, in.uv).a * in.color.a);
    return float4(rgb * alpha, alpha);
}

// The flare has no mask; its brightness is its coverage.
fragment float4 screenBloodFlareFragment(
    ScreenBloodVertexOut in [[stage_in]],
    texture2d<float> flare [[texture(TextureIndexScreenBloodColor)]],
    sampler linearSampler [[sampler(SamplerIndexTrilinear)]])
{
    float3 rgb = flare.sample(linearSampler, in.uv).rgb * in.color.rgb;
    float alpha = saturate(max(rgb.r, max(rgb.g, rgb.b)) * in.color.a);
    return float4(rgb * in.color.a, alpha);
}
