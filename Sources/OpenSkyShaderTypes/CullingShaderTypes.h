// GPU culling and temporal upscaling motion types, shared between Metal shaders and
// Swift. ShaderTypes.h includes this file after `InstanceTransform`, which it uses.

#ifndef CullingShaderTypes_h
#define CullingShaderTypes_h

#include "ShaderTypes.h"

/// GPU frustum culling (docs/rendering/gpu-culling.md): compute buffer slots.
typedef NS_ENUM(EnumBackingType, CullBufferIndex)
{
    CullBufferIndexInstances = 0,
    CullBufferIndexParameters = 1,
    CullBufferIndexOutput = 2,
    CullBufferIndexArguments = 3,
    /// Room-culled counter, then the visible-room bitset (docs/rendering/room-portal-culling.md).
    CullBufferIndexRooms = 4,
};

typedef NS_ENUM(EnumBackingType, CullConstant)
{
    /// 32-bit words in one MTLDrawIndexedPrimitivesIndirectArguments; instance count is word 1.
    CullConstantArgumentWords = 5,
    CullConstantThreadgroupWidth = 64,
};

/// One static instance the cull pass tests, written once per scene.
typedef struct
{
    InstanceTransform transform;
    /// World AABB. boundsMax.w is 1 when the instance has bounds, 0 when it is never culled.
    /// boundsMin.w is the `ReferenceFadeCategory` raw value.
    vector_float4 boundsMin;
    vector_float4 boundsMax;
    /// Indirect-argument entry the survivor counts into.
    unsigned int group;
    /// First output slot of the group.
    unsigned int outputBase;
    /// Interior room index; 0xFFFFFFFF when the instance is in no single room.
    unsigned int room;
    unsigned int padding0;
} CullInstance;

/// One view's frustum planes, inward-facing, as `Frustum` builds them.
typedef struct
{
    vector_float4 planes[6];
    /// xyz the camera; w the share of the reach the dissolve covers, 0 for no fades.
    vector_float4 fadeViewer;
    /// `ReferenceFadeDistances.shaderScales`.
    vector_float4 fadeScales;
    unsigned int instanceCount;
    /// Words in the room bitset; 0 turns room culling off for this view.
    unsigned int roomWordCount;
    unsigned int padding0;
    unsigned int padding1;
} CullParameters;

/// Temporal upscaling (docs/rendering/upscaling.md). Motion is last frame's screen
/// position minus this frame's, in texture coordinates, with the jitter removed.
typedef struct
{
    /// Undoes this frame's jittered view-projection, from depth to world.
    matrix_float4x4 inverseJitteredViewProjection;
    matrix_float4x4 viewProjection;
    matrix_float4x4 previousViewProjection;
    /// Depth below this is the first-person arms, which move with the camera.
    float nearDepthLimit;
    float padding0;
    float padding1;
    float padding2;
} UpscaleMotionUniforms;

typedef struct
{
    matrix_float4x4 current;
    matrix_float4x4 previous;
} MotionInstance;

#endif /* CullingShaderTypes_h */
