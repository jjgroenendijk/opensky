// World > Environment live bridge: the weather, animation, particle,
// precipitation and grass conformances behind that destination's panel.
// Satellite of GameViewController.swift, split out to keep both files inside
// the lint size caps; the five belong together because one sidebar
// destination drives all of them.

import AppKit
import simd

extension GameViewController: WeatherControlProviding {
    var weatherEnabled: Bool {
        get { renderer?.weatherEnabled ?? true }
        set { renderer?.weatherEnabled = newValue }
    }

    var selectableWeatherNames: [String] {
        (renderer?.weather?.store.selectableWeathers() ?? [])
            .compactMap(\.editorID)
    }

    func forceWeather(named name: String?) {
        guard let weather = renderer?.weather else { return }
        guard let name else {
            weather.forceWeather(nil, transition: .timed)
            return
        }
        let match = weather.store.selectableWeathers().first { $0.editorID == name }
        weather.forceWeather(match?.formID, transition: .timed)
    }

    func forceWeather(_ preset: WeatherPreset) {
        guard
            let weather = renderer?.weather,
            let match = weather.store.weather(for: preset)
        else { return }
        weather.forceWeather(match.formID, transition: .timed)
    }

    var currentWeatherName: String? {
        renderer?.weather?.currentWeatherEditorID
    }

    var weatherOverrideActive: Bool {
        renderer?.weather?.forced != nil
    }

    var weatherTransitionFraction: Float {
        renderer?.weather?.transitionFraction ?? 1
    }

    var weatherTransitionsPaused: Bool {
        get { renderer?.weather?.transitionsPaused ?? false }
        set { renderer?.weather?.transitionsPaused = newValue }
    }

    var windState: WindState {
        renderer?.currentWind ?? .calm
    }

    /// Scrubs the game clock's hour (issue #164). With game data present the
    /// write goes through the `GameHour` global so it journals and exercises
    /// the same redirect any script write will; the redirect moves the clock,
    /// never a stored override. Without a `GlobalStore` (demo scene) the
    /// clock is scrubbed directly. The persisted hour seeds the next launch's
    /// clock, preserving the pre-clock behaviour.
    var timeOfDay: Float {
        get { renderer?.timeOfDay ?? TimeOfDaySettings.load() }
        set {
            if
                let globalStore,
                let id = globalStore.formID(editorID: GameClock.TimeGlobal.gameHour.editorID),
                renderer != nil
            {
                worldState.setGlobal(newValue, formID: id, defaults: globalStore)
            } else {
                renderer?.timeOfDay = newValue
            }
            TimeOfDaySettings.store(newValue)
        }
    }
}

extension GameViewController: AnimationControlProviding {
    var actorAnimationsEnabled: Bool {
        get { renderer?.actorAnimationsEnabled ?? true }
        set { renderer?.actorAnimationsEnabled = newValue }
    }

    var animationSnapshot: AnimationControlSnapshot {
        AnimationControlSnapshot(
            playbackCount: renderer?.scene.animations.count ?? 0,
            updatedBoneCount: renderer?.lastAnimationUpdatedBoneCount ?? 0,
            updateMS: renderer?.lastAnimationUpdateMS ?? 0
        )
    }
}

extension GameViewController: ParticleControlProviding {
    var particlesEnabled: Bool {
        get { renderer?.particlesEnabled ?? true }
        set { renderer?.particlesEnabled = newValue }
    }

    var particlesFrozen: Bool {
        get { renderer?.particlesFrozen ?? false }
        set { renderer?.particlesFrozen = newValue }
    }

    var particleEmissionScale: Float {
        get { renderer?.particleEmissionScale ?? 1 }
        set { renderer?.particleEmissionScale = simd_clamp(newValue, 0, 2) }
    }

    var particleSnapshot: ParticleControlSnapshot {
        let playbacks = renderer?.scene.particles ?? []
        return ParticleControlSnapshot(
            systemCount: playbacks.count,
            emitterCount: playbacks.reduce(0) { $0 + $1.emitterCount },
            liveCount: playbacks.reduce(0) { $0 + $1.liveCount }
        )
    }
}

extension GameViewController: PrecipitationControlProviding {
    var precipitationEnabled: Bool {
        get { renderer?.precipitationEnabled ?? true }
        set { renderer?.precipitationEnabled = newValue }
    }

    var precipitationSnapshot: PrecipitationRuntimeSnapshot {
        renderer?.precipitation.snapshot ?? PrecipitationRuntimeSnapshot(
            state: .none,
            roofOccluded: false,
            rainLiveCount: 0,
            snowLiveCount: 0
        )
    }
}

extension GameViewController: GrassControlProviding {
    var grassEnabled: Bool {
        get { renderer?.grassEnabled ?? true }
        set { renderer?.grassEnabled = newValue }
    }

    var grassDensityScale: Float {
        get { renderer?.grassDensityScale ?? 1 }
        set { renderer?.grassDensityScale = simd_clamp(newValue, 0, 1) }
    }

    var grassDrawDistance: Float {
        get { renderer?.grassDrawDistance ?? GrassRenderPolicy.defaultDrawDistance }
        set {
            renderer?.grassDrawDistance = simd_clamp(
                newValue,
                GrassRenderPolicy.minimumDrawDistance,
                GrassRenderPolicy.maximumDrawDistance
            )
        }
    }

    var grassWindScale: Float {
        get { renderer?.grassWindScale ?? 1 }
        set {
            renderer?.grassWindScale = simd_clamp(
                newValue, 0, GrassRenderPolicy.maximumWindScale
            )
        }
    }

    var grassSnapshot: GrassControlSnapshot {
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
