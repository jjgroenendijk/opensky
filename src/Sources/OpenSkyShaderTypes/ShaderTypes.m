// SwiftPM links a clang target's object file, so the header-only OpenSkyShaderTypes
// module needs one translation unit, in Objective-C because the header imports Foundation. It declares nothing.
#include "ShaderTypes.h"
