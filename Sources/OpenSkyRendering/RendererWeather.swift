// Frame-fog resolution: active exterior weather overrides the fog uniforms, not
// interior lighting. The weather advance runs in the session (`GameSession+Weather.swift`).

import Metal
import OpenSkyRenderCore
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

    /// Where no sky draws, as in an interior or Blackreach, a gap in the geometry shows
    /// the far fog colour instead of black (docs/rendering/metal4-renderer.md).
    public static func background(fog: FrameFog, drawsSky: Bool) -> MTLClearColor {
        guard !drawsSky, fog.enabled != 0 else {
            return MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
        let colour = SIMD3<Double>(fog.farColor)
        return MTLClearColor(red: colour.x, green: colour.y, blue: colour.z, alpha: 1)
    }

    /// The frame's fog, and the background colour that follows from it.
    func resolveFrameFog(weatherLight: ResolvedWeather?) -> FrameFog {
        let fog = Self.resolvedFog(weatherLight: weatherLight, interior: interiorFog)
        sceneBackground = Self.background(fog: fog, drawsSky: scene.sky != nil)
        return fog
    }

    /// The loaded interior's fog, with a script's change when it still applies.
    var interiorFog: FogParameters? {
        frameInput.interiorFog?.fog(for: scene.lighting) ?? scene.lighting?.fog
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
