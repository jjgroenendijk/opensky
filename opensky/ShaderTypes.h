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
    /// Per-draw array of LightingConstantMaxPointLights nearest lights.
    BufferIndexPointLights = 5,
    /// Skinned-mesh second vertex stream: float4 weights + ushort4 indices.
    BufferIndexSkinningAttributes = 6,
    /// Skinned-mesh bind-pose bone matrix array.
    BufferIndexBoneMatrices = 7,
    /// CPU-simulated particle billboard instances.
    BufferIndexParticleInstances = 8,
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
    VertexAttributeBoneWeights = 6,
    VertexAttributeBoneIndices = 7,
};

typedef NS_ENUM(EnumBackingType, TextureIndex)
{
    TextureIndexDiffuse = 0,
    /// First of TerrainConstantMaxLayers consecutive layer-diffuse slots.
    TextureIndexTerrainLayer0 = 1,
    /// Sun-shadow cascade array (depth2d_array). Sits after the terrain
    /// layer slots 1..TerrainConstantMaxLayers.
    TextureIndexShadowMap = 9,
};

/// LAND splat: ATXT layer numbers run 0-7 (UESP LAND), so 8 additional layers
/// above the BTXT base is the format maximum. Vanilla data peaks around 6 per
/// quadrant (docs/formats/land.md Verification), so no real data is dropped.
typedef NS_ENUM(EnumBackingType, TerrainConstant)
{
    TerrainConstantMaxLayers = 8,
};

typedef NS_ENUM(EnumBackingType, LightingConstant)
{
    LightingConstantMaxPointLights = 8,
};

/// Cascaded sun-shadow-map config (M7.1.1). CascadeCount also sizes the
/// FrameUniforms cascade arrays; MapResolution is one shadow-array slice edge.
typedef NS_ENUM(EnumBackingType, ShadowConstant)
{
    ShadowConstantCascadeCount = 3,
    ShadowConstantMapResolution = 2048,
};

typedef NS_ENUM(EnumBackingType, SamplerIndex)
{
    SamplerIndexTrilinear = 0,
    /// Depth-compare sampler for shadow-map PCF lookups.
    SamplerIndexShadowCompare = 1,
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
    vector_float3 directionalAmbientPositiveX;
    vector_float3 directionalAmbientNegativeX;
    vector_float3 directionalAmbientPositiveY;
    vector_float3 directionalAmbientNegativeY;
    vector_float3 directionalAmbientPositiveZ;
    vector_float3 directionalAmbientNegativeZ;
    vector_float3 fogNearColor;
    vector_float3 fogFarColor;
    /// x=near, y=far, z=power, w=maximum opacity.
    vector_float4 fogDistances;
    unsigned int fogEnabled;
    /// Procedural sky clock, 0..<24. Renderer parameter, default 13:00.
    float timeOfDayHours;
    /// Deterministic frame time for animated water.
    float animationTime;
    /// World -> light-clip transform per sun-shadow cascade (M7.1.1). Valid
    /// only when shadowsEnabled != 0.
    matrix_float4x4 shadowViewProjections[ShadowConstantCascadeCount];
    /// Per-cascade far bound (view-space depth along cameraForward), padded
    /// with the last real bound. Mirrors ShadowCascadeMath.cascadeIndex.
    vector_float4 shadowCascadeSplits;
    /// Unit camera forward in world space — cascade selection projects the
    /// receiver onto it (matches the view matrix actually rendered).
    vector_float3 cameraForward;
    /// 0 -> shaders skip shadow sampling entirely (map may be stale/empty).
    unsigned int shadowsEnabled;
    /// 1.0 / ShadowConstantMapResolution — PCF tap offset in UV space.
    float shadowInverseResolution;
    /// PCF kernel radius (M7.1.2 quality): 0 -> one hardware depth-compare tap
    /// (low quality, cheapest); r>0 -> a (2r+1)^2 tap box (high quality uses 1
    /// -> the 3x3 kernel from 7.1.1). Read only when shadowsEnabled != 0.
    unsigned int shadowSampleRadius;
    /// 0 -> skyFragment uses its procedural time-of-day palette (unchanged);
    /// 1 -> it uses the blended weather sky palette below (M7.2.2).
    unsigned int weatherSkyEnabled;
    /// Weather sky palette, already time-of-day + transition blended on the
    /// CPU (WTHR NAM0 sky-upper/lower/horizon and sun/sun-glare tints).
    vector_float3 weatherSkyUpperColor;
    vector_float3 weatherSkyLowerColor;
    vector_float3 weatherHorizonColor;
    vector_float3 weatherSunColor;
    vector_float3 weatherGlareColor;
    /// Camera basis for world-space particle billboards.
    vector_float3 cameraRight;
    vector_float3 cameraUp;
} FrameUniforms;

/// One live CPU particle uploaded per frame. Vertex shader expands it into a
/// two-triangle camera-facing quad from vertex_id; no static vertex buffer.
typedef struct
{
    /// xyz world center, w billboard half-size.
    vector_float4 positionSize;
    vector_float4 color;
    /// xy UV origin, zw UV extent (NIF Subtexture Offset).
    vector_float4 uvRect;
} ParticleInstance;

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
    unsigned int pointLightCount;
    unsigned int receivesShadows;
} DrawUniforms;

typedef struct
{
    /// xyz world position, w radius.
    vector_float4 positionRadius;
    /// rgb radiance, w radial falloff exponent.
    vector_float4 colorFalloff;
} PointLightUniform;

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
    unsigned int pointLightCount;
} TerrainDrawUniforms;

/// One flat CELL water plane. Colors decode from WATR DNAM RGBX entries.
typedef struct
{
    matrix_float4x4 modelMatrix;
    vector_float3 shallowColor;
    vector_float3 deepColor;
    vector_float3 reflectionColor;
} WaterDrawUniforms;

/// Per-draw slot for the sun-shadow depth pre-pass (M7.1.1). Shares the
/// per-draw uniform ring layout (fits one 256-byte slot). lightViewProjection
/// is the cascade's world -> light-clip transform; modelMatrix is used by the
/// terrain caster (static/skinned casters read the instance/bone path). uv +
/// alphaThreshold drive the alpha-test caster's discard.
typedef struct
{
    matrix_float4x4 lightViewProjection;
    matrix_float4x4 modelMatrix;
    vector_float2 uvOffset;
    vector_float2 uvScale;
    float alphaThreshold;
} ShadowDrawUniforms;

#endif /* ShaderTypes_h */
