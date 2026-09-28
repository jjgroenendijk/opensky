// Frame-fog resolution (M7.2.2): active exterior weather overrides the fog
// uniforms without touching interior lighting. The weather advance itself runs
// in the game session (`Renderer+Weather.swift`).

import simd

extension Renderer {
    /// The frame's fog uniforms: active exterior weather fog wins, else the
    /// interior CELL/LGTM fog, else disabled (matches the pre-weather default).
    public struct FrameFog {
        public let nearColor: SIMD3<Float>
        public let farColor: SIMD3<Float>
        public let distances: SIMD4<Float>
        public let enabled: UInt32
    }

    public static func resolvedFog(
        weatherLight: ResolvedWeather?,
        interior: FogParameters?
    ) -> FrameFog {
        if let weather = weatherLight, weather.fogEnabled {
            return FrameFog(
                nearColor: weather.fogNearColor,
                farColor: weather.fogFarColor,
                distances: SIMD4(
                    weather.fogNearDistance, weather.fogFarDistance,
                    weather.fogPower, weather.fogMaximum
                ),
                enabled: 1
            )
        }
        if let fog = interior {
            return FrameFog(
                nearColor: fog.nearColor,
                farColor: fog.farColor,
                distances: SIMD4(fog.nearDistance, fog.farDistance, fog.power, fog.maximum),
                enabled: 1
            )
        }
        return FrameFog(nearColor: .zero, farColor: .zero, distances: SIMD4(0, 1, 1, 0), enabled: 0)
    }
}
