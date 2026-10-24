// How a water surface moves and catches light. The cell builder fills it from
// WATR DNAM (docs/formats/water.md); the water fragment reads it.

import simd

nonisolated public struct WaterShading: Equatable, Sendable {
    /// ANAM opacity in 0...1: how much of the body color shows where the water is shallow.
    public var opacity: Float
    public var fresnelAmount: Float
    public var reflectivity: Float
    public var sunSpecularPower: Float
    public var sunSpecularMagnitude: Float
    /// Water depth in game units where the body color starts and ends its shallow-to-deep blend.
    public var fogNear: Float
    public var fogFar: Float
    /// Three noise layers: direction in degrees, speed in tiles per second,
    /// tile size in game units, and slope strength.
    public var windDirections: SIMD3<Float>
    public var windSpeeds: SIMD3<Float>
    public var uvScales: SIMD3<Float>
    public var amplitudes: SIMD3<Float>
    /// NAM0 linear velocity, game units per second.
    public var flowVelocity: SIMD2<Float>

    public init(
        opacity: Float, fresnelAmount: Float, reflectivity: Float,
        sunSpecularPower: Float, sunSpecularMagnitude: Float,
        fogNear: Float, fogFar: Float,
        windDirections: SIMD3<Float>, windSpeeds: SIMD3<Float>,
        uvScales: SIMD3<Float>, amplitudes: SIMD3<Float>,
        flowVelocity: SIMD2<Float>
    ) {
        self.opacity = opacity
        self.fresnelAmount = fresnelAmount
        self.reflectivity = reflectivity
        self.sunSpecularPower = sunSpecularPower
        self.sunSpecularMagnitude = sunSpecularMagnitude
        self.fogNear = fogNear
        self.fogFar = fogFar
        self.windDirections = windDirections
        self.windSpeeds = windSpeeds
        self.uvScales = uvScales
        self.amplitudes = amplitudes
        self.flowVelocity = flowVelocity
    }

    /// Calm lake water, for a surface with no readable WATR.
    public static let standard = WaterShading(
        opacity: 0.3, fresnelAmount: 0.05, reflectivity: 1,
        sunSpecularPower: 1000, sunSpecularMagnitude: 3,
        fogNear: 0, fogFar: 110,
        windDirections: SIMD3(270, 210, 225), windSpeeds: SIMD3(0.02, 0.013, 0.1),
        uvScales: SIMD3(1900, 6700, 490), amplitudes: SIMD3(0.7, 0.6, 0.5),
        flowVelocity: .zero
    )
}

/// The colors and shading of one water type, as a draw item carries them.
nonisolated public struct WaterLook: Equatable, Sendable {
    public var shallowColor: SIMD3<Float>
    public var deepColor: SIMD3<Float>
    public var reflectionColor: SIMD3<Float>
    public var shading: WaterShading

    public init(
        shallowColor: SIMD3<Float>, deepColor: SIMD3<Float>, reflectionColor: SIMD3<Float>,
        shading: WaterShading = .standard
    ) {
        self.shallowColor = shallowColor
        self.deepColor = deepColor
        self.reflectionColor = reflectionColor
        self.shading = shading
    }

    /// A water type that is missing or does not decode.
    public static let fallback = WaterLook(
        shallowColor: SIMD3(0.08, 0.32, 0.42),
        deepColor: SIMD3(0.015, 0.08, 0.16),
        reflectionColor: SIMD3(0.42, 0.62, 0.78)
    )
}
