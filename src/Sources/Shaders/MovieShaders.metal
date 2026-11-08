#include "ShaderCommon.h"

// A movie picture over the whole frame (docs/engine/movies.md). The CPU builds one
// full-screen quad in clip space; its uv runs past 0 to 1 where the picture is
// letterboxed, and those pixels draw black. color.r is 1 for full-range levels.

typedef struct
{
    float4 position [[position]];
    float2 uv;
    float fullRange;
} MovieVertexOut;

vertex MovieVertexOut movieVertex(
    uint vertexID [[vertex_id]], const device UIVertex *vertices [[buffer(BufferIndexUIVertices)]])
{
    const device UIVertex &in = vertices[vertexID];
    MovieVertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    out.fullRange = in.color.r;
    return out;
}

// BT.601 YCbCr to RGB. [WARNING] The matrix Bink video uses is not confirmed.
fragment float4 movieFragment(
    MovieVertexOut in [[stage_in]],
    texture2d<float> luma [[texture(TextureIndexMovieLuma)]],
    texture2d<float> chromaBlue [[texture(TextureIndexMovieChromaBlue)]],
    texture2d<float> chromaRed [[texture(TextureIndexMovieChromaRed)]],
    sampler linearSampler [[sampler(SamplerIndexTrilinear)]])
{
    if (any(in.uv < 0.0) || any(in.uv > 1.0)) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    float y = luma.sample(linearSampler, in.uv).r;
    float cb = chromaBlue.sample(linearSampler, in.uv).r - 0.5;
    float cr = chromaRed.sample(linearSampler, in.uv).r - 0.5;
    if (in.fullRange < 0.5) {
        y = (y - 16.0 / 255.0) * (255.0 / 219.0);
        cb *= 255.0 / 224.0;
        cr *= 255.0 / 224.0;
    }
    float3 rgb = float3(y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb);
    // The movie stores gamma-encoded colour, and the sRGB target encodes on write.
    return float4(pow(saturate(rgb), 2.2), 1.0);
}
