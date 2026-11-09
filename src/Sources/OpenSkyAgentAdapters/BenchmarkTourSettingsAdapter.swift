import Metal
import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyLoading
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
public import OpenSkySessionInterface
import OpenSkyWeather
public import OpenSkyWorld
import OpenSkyWorldInterface
import QuartzCore
import simd

/// What `BenchmarkTourSettingsAdapter` reads from the session.
@MainActor
public protocol BenchmarkTourSettingsHost: AnyObject {
    var agentWorld: any AgentWorldPort { get }
    var audio: any AudioPort { get }
    var effects: any EffectsPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var playerSettingsStore: PlayerSettingsStore { get }
    var simulationClock: any SteppedWallClockPort { get }
    var terrainLODConfigurationStore: TerrainLODConfigurationStore { get }
}

/// Part of `BenchmarkWorldAdapter`, over its own narrow host.
public struct BenchmarkTourSettingsAdapter {
    public let game: any BenchmarkTourSettingsHost
    public let state: BenchmarkPartState
}

extension BenchmarkTourSettingsAdapter {
    public var activeSettings: [String: Double] {
        let store = game.playerSettingsStore
        var values: [String: Double] = [:]
        for definition in store.catalog.definitions
            where store.value(definition.id) != definition.defaultValue
        {
            values[definition.id.rawValue] = store.value(definition.id)
        }
        for (id, value) in state.tourOverrides {
            values[id.rawValue] = value
        }
        return values
    }

    public func beginTour(overrides: [PlayerSettingID: Double], passTiming: Bool) {
        guard let session = game.gameSession else { return }
        let renderer = session.renderer
        state.saved = BenchmarkWorldAdapter.SavedState(
            movementMode: session.movementMode, wasFrozen: game.simulationClock.isFrozen,
            hudEnabled: renderer.swfEnabled, camera: session.freeFlyCamera,
            forcedWeather: session.weather?.forced, outputMuted: game.audio.outputMuted
        )
        game.audio.outputMuted = state.request.muted
        state.tourOverrides = overrides
        if !overrides.isEmpty {
            apply(PlayerSettingsStore(copying: game.playerSettingsStore, overrides: overrides))
        }
        session.setMovementMode(.fly)
        renderer.swfEnabled = false
        renderer.gpuFrameLog = GPUFrameLog()
        renderer.setPassTimingEnabled(passTiming)
        game.simulationClock.freeze()
        if state.view?.startUncappedFrames() == true {
            renderer.waitsForFrameSlot = true
        }
    }

    public func tourFinished(_ result: BenchmarkTourResult) {
        state.finishAfterScreenshots(result)
    }

    public func endTour() {
        guard let session = game.gameSession, let saved = state.saved else { return }
        let renderer = session.renderer
        state.view?.stopUncappedFrames()
        renderer.waitsForFrameSlot = false
        renderer.setPassTimingEnabled(false)
        renderer.gpuFrameLog = nil
        renderer.swfEnabled = saved.hudEnabled
        if !state.tourOverrides.isEmpty {
            apply(game.playerSettingsStore)
        }
        state.tourOverrides = [:]
        game.audio.outputMuted = saved.outputMuted
        session.weather?.forceWeather(saved.forcedWeather, transition: .instant)
        session.freeFlyCamera = saved.camera
        session.setMovementMode(saved.movementMode)
        if !saved.wasFrozen {
            game.simulationClock.resume()
        }
        state.arrival = nil
        state.saved = nil
    }

    private func apply(_ store: PlayerSettingsStore) {
        game.gameSession?.applyGraphicsSettings(store)
        game.effects.applyGraphicsSettings(store)
    }

    public var loadInputs: BenchmarkLoadInputs? {
        guard
            let root = game.agentWorld.dataRoot,
            let device = game.gameSession?.renderer.device
        else {
            return nil
        }
        LoadOptimisations.activate(LoadOptimisations(settings: game.playerSettingsStore))
        return BenchmarkLoadInputs(
            root: root,
            device: device,
            terrainLOD: game.terrainLODConfigurationStore,
            decodesInParallel: game.playerSettingsStore.bool(.parallelDecode)
        )
    }
}
