// Environment controls: weather, animation, particles,
// precipitation, and grass.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyWeather
import simd

extension WorldRenderControls {
    public var weatherEnabled: Bool {
        get { gameSession?.weatherEnabled ?? true }
        set { gameSession?.weatherEnabled = newValue }
    }

    public var selectableWeatherNames: [String] {
        (gameSession?.weather?.store.selectableWeathers() ?? []).compactMap(\.editorID)
    }

    public func forceWeather(named name: String?) {
        guard let weather = gameSession?.weather else { return }
        guard let name else {
            weather.forceWeather(nil, transition: .timed)
            return
        }
        let match = weather.store.selectableWeathers().first { $0.editorID == name }
        weather.forceWeather(match?.formID, transition: .timed)
    }

    public var currentWeatherName: String? {
        gameSession?.weather?.currentWeatherEditorID
    }

    public var weatherTransitionFraction: Float {
        gameSession?.weather?.transitionFraction ?? 1
    }

    /// The same scrub as the Runtime State readout's hour control.
    public var timeOfDay: Float {
        get { gameSession?.timeOfDay ?? TimeOfDaySettings.load() }
        set { runtimeState.setGameClockHour(newValue) }
    }
}

extension WorldRenderControls {
    public var particleEmissionScale: Float {
        get { renderer?.particleEmissionScale ?? 1 }
        set { renderer?.particleEmissionScale = simd_clamp(newValue, 0, 2) }
    }
}

extension WorldRenderControls {
    public var grassDrawDistance: Float {
        get { renderer?.grassDrawDistance ?? GrassRenderPolicy.defaultDrawDistance }
        set {
            renderer?.grassDrawDistance = simd_clamp(
                newValue,
                GrassRenderPolicy.minimumDrawDistance,
                GrassRenderPolicy.maximumDrawDistance
            )
        }
    }
}
