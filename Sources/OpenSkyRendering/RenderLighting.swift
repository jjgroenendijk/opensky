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

    public init(
        nearColor: SIMD3<Float>,
        farColor: SIMD3<Float>,
        nearDistance: Float,
        farDistance: Float,
        power: Float,
        maximum: Float
    ) {
        self.nearColor = nearColor
        self.farColor = farColor
        self.nearDistance = nearDistance
        self.farDistance = farDistance
        self.power = power
        self.maximum = maximum
    }
}

nonisolated public struct RenderLighting: Equatable, Sendable {
    public let ambientColor: SIMD3<Float>
    public let directionalAmbient: DirectionalAmbientColors
    /// Unit vector: direction the cell directional light travels.
    public let directionalDirection: SIMD3<Float>
    public let directionalColor: SIMD3<Float>
    public let fog: FogParameters?

    public init(
        ambientColor: SIMD3<Float>,
        directionalAmbient: DirectionalAmbientColors,
        directionalDirection: SIMD3<Float>,
        directionalColor: SIMD3<Float>,
        fog: FogParameters?
    ) {
        self.ambientColor = ambientColor
        self.directionalAmbient = directionalAmbient
        self.directionalDirection = directionalDirection
        self.directionalColor = directionalColor
        self.fog = fog
    }
}

nonisolated public struct RenderPointLight: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let radius: Float
    public let color: SIMD3<Float>
    public let falloffExponent: Float
    /// Flicker or pulse; nil for a steady light.
    public let animation: RenderLightAnimation?

    public init(
        position: SIMD3<Float>,
        radius: Float,
        color: SIMD3<Float>,
        falloffExponent: Float,
        animation: RenderLightAnimation? = nil
    ) {
        self.position = position
        self.radius = radius
        self.color = color
        self.falloffExponent = falloffExponent
        self.animation = animation
    }

    /// Position and colour at `time` seconds; a steady light or `animated` false
    /// gives the base values.
    public func animated(
        at time: Float,
        enabled: Bool
    ) -> (position: SIMD3<Float>, color: SIMD3<Float>) {
        guard enabled, let animation else { return (position, color) }
        let sample = animation.sample(at: time)
        return (position + sample.offset, color * sample.intensity)
    }
}
