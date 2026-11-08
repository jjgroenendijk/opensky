// The menu scene: unlit meshes a menu draws in place of the world, such as the
// perk sky. Each draw carries its own camera matrix (docs/rendering/menu-scene.md).

#ifndef MenuSceneShaderTypes_h
#define MenuSceneShaderTypes_h

#include "ShaderTypesPrelude.h"

/// One vertex. Position and normal use four floats so the layout matches Swift.
typedef struct
{
    vector_float4 position;
    vector_float4 normal;
    vector_float4 color;
    vector_float2 uv;
} MenuSceneVertex;

typedef struct
{
    matrix_float4x4 modelViewProjection;
    matrix_float4x4 model;
    /// xyz the camera in world space, w the alpha-test threshold (0 is none).
    vector_float4 cameraPosition;
    /// xy the UV offset, zw the UV scale.
    vector_float4 uvTransform;
    vector_float4 effectBaseColor;
    vector_float4 effectFalloff;
    float effectBaseColorScale;
    /// EffectFlag bits.
    unsigned int effectFlags;
    /// 1 when a source texture is bound; 0 samples white.
    unsigned int hasTexture;
    /// 1 for a shape without blending: it writes alpha 1.
    unsigned int isOpaque;
} MenuSceneUniforms;

#endif /* MenuSceneShaderTypes_h */
