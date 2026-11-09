import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyRenderCore
import OpenSkyShaderTypes
import simd

/// Where an impact's decal goes.
nonisolated public enum ImpactSurface: Equatable, Sendable {
    /// A surface with a known normal, such as a wall an arrow struck.
    case surface(normal: SIMD3<Float>)
    /// An actor's body. With skin decals off, the mark goes on the ground under it.
    case actor(ReferenceKey)
    /// The ground under a foot.
    case ground
}
