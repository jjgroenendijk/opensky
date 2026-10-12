// The enum macro and simd types every shared shader header uses, in Metal and in C.

#ifndef ShaderTypesPrelude_h
#define ShaderTypesPrelude_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

#endif /* ShaderTypesPrelude_h */
