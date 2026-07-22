// Renderer-side weather glue (M7.2.2), split from Renderer/RendererAnimation/
// RendererScenePass (file-length limits): the per-frame weather advance, the
// published wind accessor, and the frame-fog resolution that lets active
// exterior weather override the fog uniforms without touching interior lighting.

import QuartzCore
import simd

extension Renderer {
    /// Published wind for precipitation/grass/particles/audio (M7.3-7.5). Calm
    /// when no weather is active.
    var currentWind: WindState {
        weatherEnabled ? weather?.currentWind ?? .calm : .calm
    }

    /// Advances the weather runtime (transition + reroll accumulation) and
    /// caches this frame's resolved weather. No weather system -> the cache
    /// stays nil and the renderer behaves exactly as before (procedural sky,
    /// camera lighting). Cheap: two resolves + one blend.
    func updateWeather(deltaTime: Float) {
        guard weatherEnabled, let weather else {
            currentResolvedWeather = nil
            return
        }
        weather.update(deltaTime: max(deltaTime, 0), hour: timeOfDay)
        currentResolvedWeather = weather.resolvedWeather?.applyingStormSkyDarkening()
    }

    func updateWeatherFromWallClock() {
        let now = CACurrentMediaTime()
        let delta = lastWeatherWallTime.map { Float(min(now - $0, 0.1)) } ?? 0
        lastWeatherWallTime = now
        updateWeather(deltaTime: delta)
    }

    /// The frame's fog uniforms: active exterior weather fog wins, else the
    /// interior CELL/LGTM fog, else disabled (matches the pre-weather default).
    struct FrameFog {
        let nearColor: SIMD3<Float>
        let farColor: SIMD3<Float>
        let distances: SIMD4<Float>
        let enabled: UInt32
    }

    static func resolvedFog(weatherLight: ResolvedWeather?, interior: FogParameters?) -> FrameFog {
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
