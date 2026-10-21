// Effect types shared between Metal shaders and Swift: particles, decals, and
// cloud layers. ShaderTypes.h includes this file.

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

/// One decal quad on a surface (docs/rendering/decals.md), built from vertex_id
/// like a particle. The two axes are half the width and height; their cross
/// product is the surface normal.
typedef struct
{
    vector_float4 center;
    vector_float4 axisU;
    vector_float4 axisV;
    /// DODT colour times the texture; alpha is the fade.
    vector_float4 color;
    /// xy UV origin, zw UV extent: one cell of a subtexture grid, or the whole texture.
    vector_float4 uvRect;
} DecalInstance;

/// One vertex of the cloud dome, in model space around the camera.
typedef struct
{
    vector_float4 position;
    vector_float4 color;
    vector_float2 texcoord;
    vector_float2 padding;
} CloudVertex;

/// One weather cloud layer drawn on its dome shape.
typedef struct
{
    /// rgb tint, a opacity.
    vector_float4 colorAlpha;
    vector_float2 uvOffset;
    vector_float2 padding;
} CloudLayerUniforms;

#endif /* EffectShaderTypes_h */
