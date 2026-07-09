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
    BufferIndexUniforms = 1,
};

typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
    VertexAttributePosition = 0,
    VertexAttributeColor = 1,
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
} Uniforms;

// vector_float3 is 16-byte aligned, so color sits at offset 16 and the
// struct stride is 32. The vertex descriptor in Renderer.swift must match.
typedef struct
{
    vector_float3 position;
    vector_float4 color;
} TriangleVertex;

#endif /* ShaderTypes_h */
