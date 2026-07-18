// Types and enum constants shared between Metal shaders and Swift.
// Memory layout is explicit + simd-aligned (AGENTS.md "Coding conventions").

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

typedef NS_ENUM(EnumBackingType, BufferIndex)
{
    BufferIndexVertices = 0,
    BufferIndexFrameUniforms = 1,
    BufferIndexDrawUniforms = 2,
    /// Terrain-only second vertex stream: two float4 splat weights per vertex.
    BufferIndexTerrainWeights = 3,
    /// Static-mesh instance transforms, tightly packed, bound at the draw
    /// group's base offset so [[instance_id]] (0-based per draw) indexes it.
    BufferIndexInstanceTransforms = 4,
};

typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
    VertexAttributePosition = 0,
    VertexAttributeColor = 1,
    VertexAttributeNormal = 2,
    VertexAttributeTexcoord = 3,
    /// Splat weights for ATXT layers 0-3 / 4-7 (terrain pipeline only).
    VertexAttributeLayerWeights0 = 4,
    VertexAttributeLayerWeights1 = 5,
};

typedef NS_ENUM(EnumBackingType, TextureIndex)
{
    TextureIndexDiffuse = 0,
    /// First of TerrainConstantMaxLayers consecutive layer-diffuse slots.
    TextureIndexTerrainLayer0 = 1,
};

/// LAND splat: ATXT layer numbers run 0-7 (UESP LAND), so 8 additional layers
/// above the BTXT base is the format maximum. Vanilla data peaks around 6 per
/// quadrant (docs/formats/land.md Verification), so no real data is dropped.
typedef NS_ENUM(EnumBackingType, TerrainConstant)
{
    TerrainConstantMaxLayers = 8,
};

typedef NS_ENUM(EnumBackingType, SamplerIndex)
{
    SamplerIndexTrilinear = 0,
};

typedef NS_ENUM(EnumBackingType, FunctionConstantIndex)
{
    FunctionConstantAlphaTest = 0,
};

// Static-mesh path (docs/todo.md 2.6). World space is Skyrim Z-up
// right-handed at native units (docs/decisions/coordinates.md); view +
// projection fold into viewProjectionMatrix.
typedef struct
{
    matrix_float4x4 viewProjectionMatrix;
    vector_float3 cameraPosition;
    /// Unit vector, direction the sunlight travels (sun -> scene).
    vector_float3 sunDirection;
    vector_float3 sunColor;
    vector_float3 ambientColor;
} FrameUniforms;

/// Per-GROUP material scalars for one instanced static-mesh draw (todo 3.2
/// instancing): every instance of the group shares them. Matrices moved to
/// InstanceTransform. Lives in the 256-byte-aligned per-draw uniform ring.
typedef struct
{
    vector_float2 uvOffset;
    vector_float2 uvScale;
    /// Material opacity multiplier (NIF BSLightingShaderProperty alpha).
    float materialAlpha;
    /// Alpha-test cutoff in [0, 1]; used only by the alpha-test variant.
    float alphaThreshold;
} DrawUniforms;

/// Per-INSTANCE transforms for the static-mesh path, in a tightly packed
/// device-address array (stride = struct size, both matrices 16-byte
/// aligned -> struct is 128 bytes with no padding). The vertex shader
/// indexes it with [[instance_id]] from the group's base offset.
typedef struct
{
    matrix_float4x4 modelMatrix;
    /// Inverse-transpose of modelMatrix: transforms normals to world space.
    matrix_float4x4 normalMatrix;
} InstanceTransform;

/// Terrain splat path (docs/todo.md 3.1): one draw per quadrant blends the
/// BTXT base with up to TerrainConstantMaxLayers ATXT diffuses by per-vertex
/// VTXT weights. Shares the DrawUniforms ring (both fit one 256-byte slot).
typedef struct
{
    matrix_float4x4 modelMatrix;
    /// Inverse-transpose of modelMatrix: transforms normals to world space.
    matrix_float4x4 normalMatrix;
    vector_float2 uvOffset;
    vector_float2 uvScale;
    /// Bound ATXT layer count, <= TerrainConstantMaxLayers.
    unsigned int layerCount;
} TerrainDrawUniforms;

#endif /* ShaderTypes_h */
