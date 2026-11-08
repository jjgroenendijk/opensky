// The `VOLI` look of the volumetric light: each weather links one record per time of
// day in `HNAM`, blended like the sky colours. Pure; see
// docs/rendering/post-effects.md#volumetric-light.

import Foundation
public import OpenSkyFormatsESM
import simd

nonisolated public struct VolumetricLightValues: Equatable, Sendable {
    /// `CNAM`; 2 gives OpenSky's earlier fixed strength.
    public var intensity: Float = 2
    /// `DNAM`: how much of `color` replaces the sun colour.
    public var customColorContribution: Float = 0
    public var color = SIMD3<Float>(1, 1, 1)
    /// `HNAM`: how much the drifting density noise thins the air.
    public var densityContribution: Float = 0
    public var densitySize: Float = 10
    public var densityWindSpeed: Float = 0
    public var densityFallingSpeed: Float = 0
    /// `LNAM`: the share of the forward phase against an even one.
    public var phaseFunctionContribution: Float = 1
    /// `MNAM`: the Henyey-Greenstein asymmetry.
    public var phaseFunctionScattering: Float = 0.6
    /// `NNAM`: 40 gives OpenSky's 4096-unit reach.
    public var samplingRangeFactor: Float = 40

    /// No `VOLI`: an interior, or a weather without the link.
    public static let fallback = Self()

    public init() {}

    public init(_ record: VolumetricLighting) {
        intensity = record.intensity ?? intensity
        customColorContribution = record.customColorContribution ?? customColorContribution
        color = record.color ?? color
        densityContribution = record.densityContribution ?? densityContribution
        densitySize = record.densitySize ?? densitySize
        densityWindSpeed = record.densityWindSpeed ?? densityWindSpeed
        densityFallingSpeed = record.densityFallingSpeed ?? densityFallingSpeed
        phaseFunctionContribution = record.phaseFunctionContribution ?? phaseFunctionContribution
        phaseFunctionScattering = record.phaseFunctionScattering ?? phaseFunctionScattering
        samplingRangeFactor = record.samplingRangeFactor ?? samplingRangeFactor
    }

    /// The weighted mean of `parts`; a slot without a record counts as `fallback`.
    public static func blend(_ parts: [(value: Self, weight: Float)]) -> Self {
        let total = parts.reduce(0) { $0 + max(0, $1.weight) }
        guard total > 0 else { return .fallback }
        func sum<Value: SIMD>(_ path: KeyPath<Self, Value>) -> Value where Value.Scalar == Float {
            parts.reduce(.zero) { $0 + $1.value[keyPath: path] * (max(0, $1.weight) / total) }
        }
        func sum(_ path: KeyPath<Self, Float>) -> Float {
            parts.reduce(0) { $0 + $1.value[keyPath: path] * (max(0, $1.weight) / total) }
        }
        var result = Self()
        result.intensity = sum(\.intensity)
        result.customColorContribution = sum(\.customColorContribution)
        result.color = sum(\.color)
        result.densityContribution = sum(\.densityContribution)
        result.densitySize = sum(\.densitySize)
        result.densityWindSpeed = sum(\.densityWindSpeed)
        result.densityFallingSpeed = sum(\.densityFallingSpeed)
        result.phaseFunctionContribution = sum(\.phaseFunctionContribution)
        result.phaseFunctionScattering = sum(\.phaseFunctionScattering)
        result.samplingRangeFactor = sum(\.samplingRangeFactor)
        return result
    }

    /// The four `HNAM` slots of each weather, weighted by the weather and the hour.
    public static func resolve(
        weathers: [(links: TimeOfDayValues<FormID?>?, weight: Float)],
        timeOfDay: TimeOfDayWeights,
        lookup: (FormID) -> VolumetricLighting?
    ) -> Self {
        let parts = weathers.flatMap { weather in
            [
                (weather.links?.sunrise, timeOfDay.sunrise), (weather.links?.day, timeOfDay.day),
                (weather.links?.sunset, timeOfDay.sunset), (weather.links?.night, timeOfDay.night)
            ].map { slot in
                (
                    value: slot.0?.flatMap(lookup).map(Self.init) ?? .fallback,
                    weight: slot.1 * weather.weight
                )
            }
        }
        return blend(parts)
    }

    /// Clamped to what the shader can draw: shares 0 to 1, the asymmetry inside -1 to 1.
    public var clamped: Self {
        func finite(_ value: Float, _ lower: Float, _ upper: Float, _ fallback: Float) -> Float {
            value.isFinite ? simd_clamp(value, lower, upper) : fallback
        }
        let base = Self.fallback
        var result = self
        result.intensity = finite(intensity, 0, 16, base.intensity)
        result.customColorContribution = finite(customColorContribution, 0, 1, 0)
        result.color = simd_clamp(color, .zero, SIMD3(repeating: 16))
        result.densityContribution = finite(densityContribution, 0, 1, 0)
        result.densitySize = finite(densitySize, 0.1, 1000, base.densitySize)
        result.densityWindSpeed = finite(densityWindSpeed, -1000, 1000, 0)
        result.densityFallingSpeed = finite(densityFallingSpeed, -1000, 1000, 0)
        result.phaseFunctionContribution = finite(phaseFunctionContribution, 0, 1, 1)
        result.phaseFunctionScattering = finite(phaseFunctionScattering, -0.95, 0.95, 0.6)
        result.samplingRangeFactor = finite(samplingRangeFactor, 1, 400, base.samplingRangeFactor)
        return result
    }
}
