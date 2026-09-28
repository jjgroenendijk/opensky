// Renderer-facing cell lighting: resolved ambient/directional/fog plus
// placed point lights. No plugin types cross into shader/renderer code.

import OpenSkyFormatsESM
import simd

nonisolated public struct FogParameters: Equatable, Sendable {
    public let nearColor: SIMD3<Float>
    public let farColor: SIMD3<Float>
    public let nearDistance: Float
    public let farDistance: Float
    public let power: Float
    public let maximum: Float
}

nonisolated public struct RenderLighting: Equatable, Sendable {
    public let ambientColor: SIMD3<Float>
    public let directionalAmbient: DirectionalAmbientColors
    /// Unit vector: direction the cell directional light travels.
    public let directionalDirection: SIMD3<Float>
    public let directionalColor: SIMD3<Float>
    public let fog: FogParameters?
}

nonisolated public struct RenderPointLight: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let radius: Float
    public let color: SIMD3<Float>
    public let falloffExponent: Float
}
