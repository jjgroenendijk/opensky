// The World > Environment controls: weather, animation, particles,
// precipitation, and grass.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import simd

extension WorldRenderControls: WeatherControlProviding {
    public var weatherEnabled: Bool {
        get { renderer?.weatherEnabled ?? true }
        set { renderer?.weatherEnabled = newValue }
    }

    public var selectableWeatherNames: [String] {
        (renderer?.weather?.store.selectableWeathers() ?? []).compactMap(\.editorID)
    }

    public func forceWeather(named name: String?) {
        guard let weather = renderer?.weather else { return }
        guard let name else {
            weather.forceWeather(nil, transition: .timed)
            return
        }
        let match = weather.store.selectableWeathers().first { $0.editorID == name }
        weather.forceWeather(match?.formID, transition: .timed)
    }

    public func forceWeather(_ preset: WeatherPreset) {
        guard
            let weather = renderer?.weather,
            let match = weather.store.weather(for: preset)
        else { return }
        weather.forceWeather(match.formID, transition: .timed)
    }

    public var currentWeatherName: String? {
        renderer?.weather?.currentWeatherEditorID
    }

    public var weatherOverrideActive: Bool {
        renderer?.weather?.forced != nil
    }

    public var weatherTransitionFraction: Float {
        renderer?.weather?.transitionFraction ?? 1
    }

    public var weatherTransitionsPaused: Bool {
        get { renderer?.weather?.transitionsPaused ?? false }
        set { renderer?.weather?.transitionsPaused = newValue }
    }

    public var windState: WindState {
        renderer?.currentWind ?? .calm
    }

    /// The same scrub as the Runtime State panel's hour control.
    public var timeOfDay: Float {
        get { renderer?.timeOfDay ?? TimeOfDaySettings.load() }
        set { runtimeState.setGameClockHour(newValue) }
    }
}

extension WorldRenderControls: AnimationControlProviding {
    public var actorAnimationsEnabled: Bool {
        get { renderer?.actorAnimationsEnabled ?? true }
        set { renderer?.actorAnimationsEnabled = newValue }
    }

    public var animationSnapshot: AnimationControlSnapshot {
        AnimationControlSnapshot(
            playbackCount: renderer?.scene.animations.count ?? 0,
            updatedBoneCount: renderer?.lastAnimationUpdatedBoneCount ?? 0,
            updateMS: renderer?.lastAnimationUpdateMS ?? 0
        )
    }
}

extension WorldRenderControls: ParticleControlProviding {
    public var particlesEnabled: Bool {
        get { renderer?.particlesEnabled ?? true }
        set { renderer?.particlesEnabled = newValue }
    }

    public var particlesFrozen: Bool {
        get { renderer?.particlesFrozen ?? false }
        set { renderer?.particlesFrozen = newValue }
    }

    public var particleEmissionScale: Float {
        get { renderer?.particleEmissionScale ?? 1 }
        set { renderer?.particleEmissionScale = simd_clamp(newValue, 0, 2) }
    }

    public var particleSnapshot: ParticleControlSnapshot {
        let playbacks = renderer?.scene.particles ?? []
        return ParticleControlSnapshot(
            systemCount: playbacks.count,
            emitterCount: playbacks.reduce(0) { $0 + $1.emitterCount },
            liveCount: playbacks.reduce(0) { $0 + $1.liveCount }
        )
    }
}

extension WorldRenderControls: WaterControlProviding {
    public var waterDepthEnabled: Bool {
        get { renderer?.waterDepth.enabled ?? world?.playerSettingsStore.bool(.waterDepth) ?? true }
        set {
            renderer?.waterDepth.enabled = newValue
            world?.playerSettingsStore.set(.waterDepth, to: newValue ? 1 : 0)
        }
    }

    public var waterSurfaceCount: Int {
        renderer?.scene.water.count ?? 0
    }
}

extension WorldRenderControls: PrecipitationControlProviding {
    public var precipitationEnabled: Bool {
        get { renderer?.precipitationEnabled ?? true }
        set { renderer?.precipitationEnabled = newValue }
    }

    public var precipitationSnapshot: PrecipitationRuntimeSnapshot {
        renderer?.precipitation.snapshot ?? PrecipitationRuntimeSnapshot(
            state: .none,
            roofOccluded: false,
            rainLiveCount: 0,
            snowLiveCount: 0
        )
    }

    public var precipitationTuning: PrecipitationTuning {
        renderer?.precipitation.tuning ?? .fallback
    }

    public var weatherVolumetricLighting: String? {
        guard
            let renderer, let weather = renderer.weather,
            let links = renderer.session.imageSpaceLinks
        else { return nil }
        return weather.volumetricLighting(
            in: links.records, plugin: links.weatherPlugin, hour: renderer.timeOfDay
        )
    }
}

extension WorldRenderControls: GrassControlProviding {
    public var grassEnabled: Bool {
        get { renderer?.grassEnabled ?? true }
        set { renderer?.grassEnabled = newValue }
    }

    public var grassDensityScale: Float {
        get { renderer?.grassDensityScale ?? 1 }
        set { renderer?.grassDensityScale = simd_clamp(newValue, 0, 1) }
    }

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

    public var grassWindScale: Float {
        get { renderer?.grassWindScale ?? 1 }
        set {
            renderer?.grassWindScale = simd_clamp(newValue, 0, GrassRenderPolicy.maximumWindScale)
        }
    }

    public var grassSnapshot: GrassControlSnapshot {
        let stats = renderer?.lastGrassDrawStats ?? GrassDrawStats()
        return GrassControlSnapshot(
            sceneInstances: stats.sceneInstances,
            drawnInstances: stats.drawnInstances,
            drawCalls: stats.drawCalls,
            distanceCulledInstances: stats.distanceCulledInstances,
            densityCulledInstances: stats.densityCulledInstances,
            frustumCulledInstances: stats.frustumCulledInstances,
            budgetDroppedInstances: stats.budgetDroppedInstances
        )
    }
}
