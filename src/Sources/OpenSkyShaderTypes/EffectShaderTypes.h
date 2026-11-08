// Effect types shared between Metal shaders and Swift: particles, decals, cloud
// layers, and sky objects. ShaderTypes.h includes this file.

#ifndef EffectShaderTypes_h
#define EffectShaderTypes_h

#include "ShaderTypesPrelude.h"

/// One live CPU particle uploaded per frame. Vertex shader expands it into a
/// two-triangle camera-facing quad from vertex_id; no static vertex buffer.
typedef struct
{
    /// xyz world center, w billboard half-size.
    vector_float4 positionSize;
    vector_float4 color;
    /// xy UV origin, zw UV extent (NIF Subtexture Offset).
    vector_float4 uvRect;
    /// x cosine, y sine of the billboard turn; zw unused.
    vector_float4 rotation;
} ParticleInstance;

/// The effect shader of one particle system, written once per frame in flight.
typedef struct
{
    /// EffectFlag bits.
    unsigned int flags;
    unsigned int pointLightCount;
    float baseColorScale;
    /// Depth in world units over which a soft system fades in.
    float softDepth;
    vector_float4 baseColor;
    /// Falloff start and stop cosines, then start and stop opacity.
    vector_float4 falloff;
    /// x: share of the scene light, 0 to 1. y: 1 when the blend adds light. zw unused.
    vector_float4 lighting;
    /// The reference's `XEMI` colour; alpha 1 when known.
    vector_float4 emittance;
} ParticleEffectUniforms;

/// One decal quad on a surface (docs/rendering/decals.md), built from vertex_id
/// like a particle. The two axes are half the width and height; their cross
/// product is the surface normal.
typedef struct
{
    /// w: half the depth of a projected decal's box; 0 draws a flat quad.
    vector_float4 center;
    vector_float4 axisU;
    vector_float4 axisV;
    /// DODT colour times the texture; alpha is the fade.
    vector_float4 color;
    /// xy UV origin, zw UV extent: one cell of a subtexture grid, or the whole texture.
    vector_float4 uvRect;
} DecalInstance;

/// One vertex of the cloud dome or a sky mesh, in model space around the camera.
typedef struct
{
    vector_float4 position;
    vector_float4 color;
    vector_float2 texcoord;
    vector_float2 padding;
    /// xyz unit normal; the effect falloff of a sky mesh reads it.
    vector_float4 normal;
} CloudVertex;

/// One weather cloud layer drawn on its dome shape.
typedef struct
{
    /// rgb tint, a opacity.
    vector_float4 colorAlpha;
    vector_float2 uvOffset;
    /// Added to the gamma colour: the scene scale times the image space sky scale.
    float lift;
    float padding;
} CloudLayerUniforms;

typedef NS_ENUM(EnumBackingType, SkyObjectFlag)
{
    /// Adds to the sky instead of covering it.
    SkyObjectFlagAdditive = 1 << 0,
    /// Only the texture's alpha is used; the colour is the tint alone.
    SkyObjectFlagAlphaOnly = 1 << 1,
};

/// A sun, glare, or moon card, or a star or aurora mesh, drawn behind everything.
typedef struct
{
    /// Mesh only: model space to world directions around the camera.
    matrix_float4x4 rotation;
    /// rgb tint, a opacity.
    vector_float4 color;
    /// Card only: xyz unit direction to its middle, w half its width over distance.
    vector_float4 center;
    vector_float4 right;
    vector_float4 up;
    /// Mesh only: the shape's effect shading, as in DrawUniforms.
    vector_float4 falloff;
    vector_float4 baseColor;
    float baseColorScale;
    /// SkyObjectFlag bits.
    unsigned int flags;
    /// EffectFlag bits; 0 for a card.
    unsigned int effectFlags;
    unsigned int padding;
    /// Mesh only: UV offset in xy, scale in zw.
    vector_float4 uvTransform;
} SkyObjectUniforms;

#endif /* EffectShaderTypes_h */
