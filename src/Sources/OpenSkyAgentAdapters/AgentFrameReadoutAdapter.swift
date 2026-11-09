import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyDiagnostics
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AgentFrameReadoutAdapter` reads from the session.
@MainActor
public protocol AgentFrameReadoutHost: AnyObject {
    var gameSession: (any GameSessionPort)? { get }
    var renderControls: any WorldRenderControlsPort { get }
    var renderer: (any RendererPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var streamer: any CellStreamerPort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentFrameReadoutAdapter {
    public let hub: AgentHub
    public let game: any AgentFrameReadoutHost
}

extension AgentFrameReadoutAdapter {
    public func globalState(_ editorID: String) throws(AgentFailure) -> AgentJSON {
        guard let global = game.runtimeState.runtimeStateGlobal(editorID: editorID) else {
            throw AgentFailure(.notFound, "no global '\(editorID)'")
        }
        return [
            "id": .string(global.editorID), "value": .init(global.currentValue),
            "default": .init(global.defaultValue), "overridden": .bool(global.isOverridden)
        ]
    }

    public func timeState() -> AgentJSON {
        let clock = game.runtimeState.runtimeStateClock
        return [
            "hour": .init(clock.hourOfDay), "day": .init(clock.day),
            "month": .string(clock.monthName),
            "year": .init(clock.year), "daysPassed": .init(clock.daysPassed),
            "timescale": .init(clock.timescale), "simulation": hub.agentTimeline.json,
            "sky": skyState()
        ]
    }

    /// The sun path, the moons, and the aurora this frame draws; null without weather.
    private func skyState() -> AgentJSON {
        guard let sky = game.gameSession?.celestialSky else { return .null }
        let drawn = game.renderer?.skyCelestial?.drawnObjectCount
        return [
            "sunDirection": .init(sky.sunDirection), "lightDirection": .init(sky.lightDirection),
            "sunAlpha": .init(sky.sunAlpha), "glareScale": .init(sky.glareScale),
            "starsAngleDegrees": .init(MatrixMath.degrees(fromRadians: sky.starsAngle)),
            "moonGlare": game.gameSession?.currentResolvedWeather
                .map { .init($0.moonGlare) } ?? .null,
            "moons": .array(sky.moons.map { moon in
                [
                    "moon": .string(moon.moon.rawValue), "phase": .string(moon.phase.textureSuffix),
                    "direction": .init(moon.direction), "alpha": .init(moon.alpha)
                ]
            }),
            "auroras": .array(sky.auroras.map { aurora in
                ["model": .string(aurora.model), "alpha": .init(aurora.alpha)]
            }),
            "drawnObjects": drawn.map { .init($0) } ?? .null
        ]
    }

    public func frameState() -> AgentJSON {
        let stats = game.renderControls.frameStatsSnapshot
        return [
            "timeline": hub.agentTimeline.json,
            "fps": .number(stats.fps), "frameMS": .number(stats.frameMS),
            "maxFrameMS": .number(stats.maxFrameMS),
            "skippedFrames": .init(game.gameSession?.renderer.skippedFrames ?? 0),
            "gpuMS": stats.gpuMS.map(AgentJSON.number) ?? .null,
            "memoryMB": MemoryFootprint.physFootprintMB().map(AgentJSON.number) ?? .null,
            "interpolation": interpolationState(),
            "terrainLOD": terrainLODState(),
            "largeReferences": .init(game.streamer.largeReferenceCount),
            "fullLODReferences": .init(game.streamer.fullLODReferenceCount),
            "generatedTerrainBlocks": .init(game.streamer.generatedTerrainBlockCount),
            "hiddenLargeReferenceLOD": .init(game.streamer.hiddenLargeReferenceSegments),
            "screenFade": screenFadeState(),
            "postEffects": hub.render.postEffectState(),
            "lighting": hub.render.lightingState(),
            "projectileVisuals": hub.render.projectileVisualState(),
            "soundMix": hub.render.soundMixState(),
            "treeWind": hub.render.treeWindState(),
            "waterFlow": hub.render.waterFlowState(),
            "precipitation": hub.render.precipitationState(),
            "gpuMemory": gpuMemoryState()
        ]
    }

    /// Walks the residency set, so a read can take 100 ms in a large world.
    private func gpuMemoryState() -> AgentJSON {
        guard let renderer = game.gameSession?.renderer else { return .null }
        let usage = renderer.gpuMemoryUsage()
        let cached = game.streamer.cachedAssetCounts
        let mebibyte = Double(1 << 20)
        return [
            "totalMB": .number(Double(usage.totalBytes) / mebibyte),
            "renderTargetMB": .number(Double(usage.renderTargetBytes) / mebibyte),
            "textureMB": .number(Double(usage.textureBytes) / mebibyte),
            "bufferMB": .number(Double(usage.bufferBytes) / mebibyte),
            "residentCount": .init(usage.residentCount),
            "retiredEntries": .init(renderer.retired.count),
            "streamedTextures": .init(usage.streamedTextures),
            "streamedReservedMB": .number(Double(usage.streamedReservedBytes) / mebibyte),
            "streamedUsedMB": .number(Double(usage.streamedUsedBytes) / mebibyte),
            "cachedTextures": cached.map { .init($0.textures) } ?? .null,
            "cachedModels": cached.map { .init($0.models) } ?? .null
        ]
    }

    /// The `Game.FadeOutGame` fader: its colour, how much it covers, and whether it moves.
    public func screenFadeState() -> AgentJSON {
        guard let fade = game.gameSession?.imageSpace.screenFade else { return .null }
        return [
            "colour": .string(fade.colour == .zero ? "black" : "white"),
            "cover": .init(fade.cover), "running": .bool(fade.isRunning)
        ]
    }

    private func terrainLODState() -> AgentJSON {
        guard let curve = game.renderControls.terrainLODBrightness else { return .null }
        return [
            "brighteningGain": .init(curve.gain),
            "brighteningExponent": .init(curve.exponent),
            "darkeningFactor": .init(curve.typicalFactor)
        ]
    }

    private func interpolationState() -> AgentJSON {
        guard let status = game.renderControls.renderPerformanceSnapshot?.frameInterpolation
        else { return .null }
        return [
            "enabled": .bool(status.enabled), "running": .bool(status.isRunning),
            "shownFPS": .number(status.shownFPS),
            "builtFrames": .init(status.interpolatedFrames),
            "presentLatencyMS": status.presentLatencyMS.map(AgentJSON.number) ?? .null,
            "frameGapMS": status.pacing.map { .number($0.averageGapMS) } ?? .null,
            "longestFrameGapMS": status.pacing.map { .number($0.longestGapMS) } ?? .null,
            "hitches": status.pacing.map { .init($0.hitches) } ?? .null
        ]
    }

    /// The weathers the frame draws, with their weights, so a fade that has not
    /// finished shows next to the reported weather.
    public func weatherReport(_ weather: (any WeatherSystemPort)?) -> [String: AgentJSON] {
        guard let weather else { return ["weather": .null, "weatherBlend": .null] }
        let blend = AgentJSON.array(weather.blendedWeathers.map { entry in
            [
                "weather": weather.store.weather(entry.weather)?.editorID.map(AgentJSON.string)
                    ?? .formID(entry.weather.rawValue),
                "weight": .init(entry.weight)
            ]
        })
        return ["weather": .init(weather.currentWeatherEditorID), "weatherBlend": blend]
    }
}
