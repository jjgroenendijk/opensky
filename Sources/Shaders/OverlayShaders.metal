#include "ShaderCommon.h"

// Depth-tested world-space debug overlay. Triangles and line segments share
// one vertex/color pipeline; CPU submission groups the two topologies into
// adjacent ranges of the same per-frame upload.

typedef struct
{
    float4 position [[position]];
    float4 color;
} OverlayVertexOut;

vertex OverlayVertexOut overlayVertex(
    uint vertexID [[vertex_id]],
    const device OverlayVertex *vertices [[buffer(BufferIndexOverlayVertices)]],
    constant FrameUniforms &frame [[buffer(BufferIndexFrameUniforms)]])
{
    const device OverlayVertex &in = vertices[vertexID];
    OverlayVertexOut out;
    out.position = frame.viewProjectionMatrix * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 overlayFragment(OverlayVertexOut in [[stage_in]])
{
    float alpha = saturate(in.color.a);
    return float4(in.color.rgb * alpha, alpha);
}

// Screen-space 2D UI overlay, drawn last with depth off. Vertices are
// framebuffer pixels (top-left origin, y down), read by vertex_id. One pipeline
// draws fills and text: fills sample the atlas white texel, glyphs their
// coverage cell. Output is premultiplied for the premultiplied-over blend.

typedef struct
{
    float4 position [[position]];
    float2 uv;
    float4 color;
} UIVertexOut;

vertex UIVertexOut uiVertex(
    uint vertexID [[vertex_id]],
    const device UIVertex *vertices [[buffer(BufferIndexUIVertices)]],
    constant UIFrameUniforms &frame [[buffer(BufferIndexUIUniforms)]])
{
    const device UIVertex &in = vertices[vertexID];
    float2 normalized = in.position / frame.viewportSize;
    UIVertexOut out;
    // Pixel origin top-left, y down -> NDC origin center, y up. z = 0 keeps UI
    // in front; the pass runs depth-test-always with writes off.
    out.position = float4(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0, 0.0, 1.0);
    out.uv = in.uv;
    out.color = in.color;
    return out;
}

fragment float4 uiFragment(
    UIVertexOut in [[stage_in]],
    texture2d<float> atlas [[texture(TextureIndexUIAtlas)]],
    sampler uiSampler [[sampler(SamplerIndexUIAtlas)]])
{
    float coverage = atlas.sample(uiSampler, in.uv).r;
    float alpha = in.color.a * coverage;
    return float4(in.color.rgb * alpha, alpha);
}

// SWF display-list layer, drawn after the 3D scene and before the dev UI.
// Each draw carries its own transform in SWFDrawUniforms. Fills resolve in
// straight alpha, apply the CXFORM, then premultiply for blending. Clip layers
// use the stencil-only swfMaskFragment.

typedef struct
{
    float4 position [[position]];
    float2 uv;
    float2 fillPosition;
} SWFVertexOut;

static inline float2 swfApplyAffine(float4 rotation, float2 translation, float2 p)
{
    return float2(
        rotation.x * p.x + rotation.z * p.y + translation.x,
        rotation.y * p.x + rotation.w * p.y + translation.y);
}

vertex SWFVertexOut swfVertex(
    uint vertexID [[vertex_id]],
    const device SWFVertex *vertices [[buffer(BufferIndexSWFVertices)]],
    constant SWFDrawUniforms &draw [[buffer(BufferIndexSWFUniforms)]])
{
    const device SWFVertex &in = vertices[vertexID];
    float2 clip = swfApplyAffine(draw.transformRotation, draw.transformTranslation, in.position);
    SWFVertexOut out;
    out.position = float4(clip, 0.0, 1.0);
    out.uv = in.uv;
    out.fillPosition = swfApplyAffine(draw.fillRotation, draw.fillTranslation, in.position);
    return out;
}

/// SpreadMode folding of the raw gradient parameter into 0..1 (spec p. 135).
static inline float swfSpread(float t, uint mode)
{
    if (mode == SWFGradientSpreadRepeat) {
        return fract(t);
    }
    if (mode == SWFGradientSpreadReflect) {
        float period = fract(t * 0.5) * 2.0;
        return period <= 1.0 ? period : 2.0 - period;
    }
    return saturate(t);
}

fragment float4 swfFragment(
    SWFVertexOut in [[stage_in]],
    constant SWFDrawUniforms &draw [[buffer(BufferIndexSWFUniforms)]],
    texture2d<float> glyphAtlas [[texture(TextureIndexUIAtlas)]],
    texture2d<float> bitmap [[texture(TextureIndexSWFBitmap)]],
    texture2d<float> gradientRamp [[texture(TextureIndexSWFGradient)]],
    sampler clampSampler [[sampler(SamplerIndexUIAtlas)]],
    sampler repeatSampler [[sampler(SamplerIndexSWFRepeat)]])
{
    float4 straight = draw.baseColor;
    switch (draw.fillMode) {
    case SWFFillModeGlyph:
        straight.a *= glyphAtlas.sample(clampSampler, in.uv).r;
        break;
    case SWFFillModeBitmap: {
        float4 sampled = draw.bitmapTiled != 0 ? bitmap.sample(repeatSampler, in.fillPosition)
                                               : bitmap.sample(clampSampler, in.fillPosition);
        if (draw.sourcePremultiplied != 0 && sampled.a > 0.0) {
            sampled.rgb /= sampled.a;
        }
        straight = sampled;
        break;
    }
    case SWFFillModeLinearGradient:
    case SWFFillModeRadialGradient: {
        // Gradient square: fillPosition is normalized to -1..1; the linear
        // parameter runs left -> right, the radial one out from the center
        // (spec chapter 7, pp. 134-136).
        float raw = draw.fillMode == SWFFillModeLinearGradient ? in.fillPosition.x * 0.5 + 0.5
                                                               : length(in.fillPosition);
        float t = swfSpread(raw, draw.gradientSpread);
        straight = gradientRamp.sample(clampSampler, float2(t, draw.gradientV));
        break;
    }
    default:
        break;
    }
    straight = saturate(straight * draw.colorMultiply + draw.colorAdd);
    return float4(straight.rgb * straight.a, straight.a);
}

/// Stencil-only mask draws: zero premultiplied output leaves the color
/// attachment untouched under the pass's blending, so the mask pipeline needs
/// no color-write-mask special case; only the stencil operation matters.
fragment float4 swfMaskFragment(SWFVertexOut in [[stage_in]])
{
    return float4(0.0);
}
