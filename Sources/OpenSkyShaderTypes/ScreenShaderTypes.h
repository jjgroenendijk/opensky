// Screen-space types shared between Metal shaders and Swift: UI, overlay, SWF,
// and the full-screen passes. ShaderTypes.h includes this file.

#ifndef ScreenShaderTypes_h
#define ScreenShaderTypes_h

#include "ShaderTypesPrelude.h"

/// One screen-space UI vertex. Position is in framebuffer pixels (origin
/// top-left, y down); the vertex shader maps it to NDC via UIFrameUniforms.
/// uv samples the r8 atlas (white texel -> solid fill, glyph cell -> text).
/// color is straight (non-premultiplied) RGBA; the fragment premultiplies.
typedef struct
{
    vector_float2 position;
    vector_float2 uv;
    vector_float4 color;
} UIVertex;

/// Per-frame UI uniforms. viewportSize is the framebuffer pixel size the
/// vertex shader divides by to reach NDC.
typedef struct
{
    vector_float2 viewportSize;
} UIFrameUniforms;

/// One world-space debug-overlay vertex. Position stays in engine coordinates
/// and FrameUniforms.viewProjectionMatrix maps it to clip space. Color is
/// straight RGBA; the fragment shader premultiplies before blending.
typedef struct
{
    vector_float3 position;
    vector_float4 color;
} OverlayVertex;

/// How the SWF fragment shader resolves a draw's color.
typedef NS_ENUM(EnumBackingType, SWFFillMode)
{
    /// baseColor as-is (solid fill).
    SWFFillModeSolid = 0,
    /// Sample the per-draw bitmap texture at the fill-space position.
    SWFFillModeBitmap = 1,
    /// baseColor with alpha scaled by the UI glyph atlas coverage at uv.
    SWFFillModeGlyph = 2,
    /// Sample the gradient ramp at the linear-gradient parameter.
    SWFFillModeLinearGradient = 3,
    /// Sample the gradient ramp at the radial-gradient parameter.
    SWFFillModeRadialGradient = 4,
};

/// GRADIENT SpreadMode (SWF spec v19 p. 135) applied to the ramp parameter.
typedef NS_ENUM(EnumBackingType, SWFGradientSpread)
{
    SWFGradientSpreadPad = 0,
    SWFGradientSpreadReflect = 1,
    SWFGradientSpreadRepeat = 2,
};

/// One SWF display-list vertex. Shape meshes carry twip-space positions with
/// unused uv; glyph quads carry framebuffer-pixel positions with UI-atlas uv.
/// The per-draw transform maps either space to clip coordinates.
typedef struct
{
    vector_float2 position;
    vector_float2 uv;
} SWFVertex;

/// Per-draw uniforms for one SWF display-list draw. Both 2x3 affine
/// transforms are stored as a rotation/scale block (a, b, c, d) plus a
/// translation: out.x = a*x + c*y + tx, out.y = b*x + d*y + ty.
typedef struct
{
    /// Vertex space -> clip (NDC) transform: the concatenated
    /// place-matrix -> movie -> viewport -> NDC mapping.
    vector_float4 transformRotation;
    vector_float2 transformTranslation;
    /// Vertex space -> fill space: bitmap fills reach normalized 0..1 texture
    /// coordinates, gradient fills reach the -1..1 gradient square.
    vector_float4 fillRotation;
    vector_float2 fillTranslation;
    /// CXFORM terms in the straight-alpha 0..1 domain: multiply then add.
    vector_float4 colorMultiply;
    vector_float4 colorAdd;
    /// Straight-alpha fill color for solid fills and glyph text.
    vector_float4 baseColor;
    /// Ramp-row v coordinate for gradient fills.
    float gradientV;
    /// SWFFillMode.
    unsigned int fillMode;
    /// SWFGradientSpread for gradient fills.
    unsigned int gradientSpread;
    /// 1 -> the bound bitmap texture stores premultiplied alpha (Lossless2
    /// ARGB); the shader unpremultiplies before applying the CXFORM.
    unsigned int sourcePremultiplied;
    /// 1 -> tiled bitmap fill (repeat sampler), 0 -> clipped (clamp).
    unsigned int bitmapTiled;
} SWFDrawUniforms;

/// The image-space composite (docs/rendering/image-space.md). Colors are linear.
typedef struct
{
    /// rgb tint color, a tint amount.
    vector_float4 tint;
    /// rgb fade color, a fade amount.
    vector_float4 fade;
    /// saturation, brightness, contrast, blur radius in target pixels.
    vector_float4 grading;
    /// x double-vision strength; yzw unused.
    vector_float4 extra;
    /// x exposure, y white point (0 is none), z 1 to measure luminance, w unused.
    vector_float4 toneMapping;
} ImageSpaceUniforms;

/// One effect-shader membrane drawn additively over its target's meshes
/// (docs/rendering/visual-effects.md). Colors are linear and premultiplied by alpha.
typedef struct
{
    /// rgb fill color times the fill alpha; a unused.
    vector_float4 fill;
    /// rgb edge color times the edge alpha; a the edge falloff exponent.
    vector_float4 edge;
} MembraneUniforms;

#endif /* ScreenShaderTypes_h */
