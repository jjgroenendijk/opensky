// The renderer and streamer controls behind the World panels: shadows, terrain
// LOD, render debug, camera, frame and scene stats, triggers, and physics.
// Without a renderer or a streamer every read degrades to a stated default.

import OpenSkyDiagnostics
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering

/// What `WorldRenderControls` reads from the app.
@MainActor
public protocol RenderControlWorld: AnyObject {
    /// Nil when the GPU lacks Metal 4.
    var renderer: Renderer? { get }
    /// Nil without game data.
    var streamer: CellStreamer? { get }
    var terrainLODConfigurationStore: TerrainLODConfigurationStore { get }
    /// The player settings, for the switches that apply on the next launch.
    var playerSettingsStore: PlayerSettingsStore { get }
    func refocusGameView()
}

@MainActor
public final class WorldRenderControls {
    weak var world: (any RenderControlWorld)?
    /// The time-of-day control scrubs the clock through the runtime state, so
    /// the scrub is journalled.
    let runtimeState: RuntimeStateCoordinator

    var renderer: Renderer? {
        world?.renderer
    }

    var streamer: CellStreamer? {
        world?.streamer
    }

    public init(runtimeState: RuntimeStateCoordinator) {
        self.runtimeState = runtimeState
    }

    public func attach(world: any RenderControlWorld) {
        self.world = world
    }
}

extension WorldRenderControls: ShadowControlProviding {
    /// Not persisted: an A/B flip is a short comparison, and a shadowless world
    /// on the next launch would read as a bug.
    public var sunShadowsEnabled: Bool {
        get { renderer?.sunShadowsEnabled ?? true }
        set { renderer?.sunShadowsEnabled = newValue }
    }

    public var shadowQuality: ShadowQuality {
        get { renderer?.shadowQuality ?? ShadowQualitySettings.load() }
        set {
            renderer?.shadowQuality = newValue
            ShadowQualitySettings.store(newValue)
        }
    }

    public var shadowDrawStats: ShadowDrawStats {
        renderer?.lastShadowDrawStats ?? ShadowDrawStats()
    }

    public var shadowUpdateMS: Double {
        renderer?.lastShadowUpdateMS ?? 0
    }

    public var shadowsActive: Bool {
        renderer?.shadowRenders ?? false
    }

    public func refocusGameView() {
        world?.refocusGameView()
    }
}

extension WorldRenderControls: TerrainLODControlProviding {
    public var terrainLODConfigurationSnapshot: TerrainLODConfigurationSnapshot {
        world?.terrainLODConfigurationStore.snapshot() ?? TerrainLODConfigurationSnapshot(
            configuration: .fallback, source: "safe defaults"
        )
    }

    public var terrainLODOverrideActive: Bool {
        TerrainLODSettings.hasOverride()
    }

    public func applyTerrainLODConfiguration(_ configuration: TerrainLODConfiguration) -> Bool {
        guard configuration.isValid else { return false }
        TerrainLODSettings.store(configuration)
        world?.terrainLODConfigurationStore.replace(with: TerrainLODConfigurationSnapshot(
            configuration: configuration,
            source: "OpenSky sidebar override"
        ))
        streamer?.invalidateDistantLOD()
        return true
    }

    public func resetTerrainLODConfiguration() {
        TerrainLODSettings.clearOverride()
        let root = try? GameDataLocator.locate()
        world?.terrainLODConfigurationStore.replace(with: TerrainLODSettings.load(root: root))
        streamer?.invalidateDistantLOD()
    }
}

extension WorldRenderControls: RenderDebugControlProviding {
    public var renderDebugMode: RenderDebugMode {
        get { renderer?.renderDebug.mode ?? .off }
        set { renderer?.renderDebug.mode = newValue }
    }

    public var renderDebugLayers: RenderLayer {
        get { renderer?.renderDebug.layers ?? .all }
        set { renderer?.renderDebug.layers = newValue }
    }

    public var renderDebugSnapshot: RenderDebugControlSnapshot {
        RenderDebugControlSnapshot(
            mode: renderDebugMode,
            layers: renderDebugLayers,
            effectiveLayers: renderer?.effectiveRenderLayers ?? .all,
            stats: renderer?.lastDrawStats ?? SceneDrawStats(),
            shadowStats: renderer?.lastShadowDrawStats ?? ShadowDrawStats()
        )
    }
}

extension WorldRenderControls: RenderPerformanceControlProviding {
    public var renderPerformanceSnapshot: RenderPerformanceSnapshot? {
        guard let renderer else { return nil }
        return RenderPerformanceSnapshot(
            renderTargets: renderer.renderTargetMemory(),
            pipelineCache: renderer.pipelineCache.stats
        )
    }

    /// Read at renderer setup, so a change applies on the next launch.
    public var pipelineCacheEnabled: Bool {
        get { world?.playerSettingsStore.bool(.pipelineCacheEnabled) ?? true }
        set { world?.playerSettingsStore.set(.pipelineCacheEnabled, to: newValue ? 1 : 0) }
    }

    @discardableResult
    public func clearPipelineCache() -> Int {
        guard
            let store = world?.playerSettingsStore,
            let folder = PipelineCache.archiveFolder(store: store)
        else { return 0 }
        return (try? PipelineCacheFolder.clear(folder: folder)) ?? 0
    }
}

extension WorldRenderControls: CameraControlProviding {
    public var cameraPose: CameraPoseSnapshot {
        guard let renderer else { return .unavailable }
        let camera = renderer.freeFlyCamera
        return CameraPoseSnapshot(
            position: camera.position,
            yaw: camera.yaw,
            pitch: camera.pitch,
            cell: CellGridManager.cellCoordinate(for: camera.position),
            movementMode: renderer.movementMode
        )
    }

    public var movementMode: CameraMovementMode {
        get { renderer?.movementMode ?? .fly }
        set { renderer?.setMovementMode(newValue) }
    }

    public var movementConfiguration: PlayerMovementConfiguration {
        renderer?.walkController.configuration ?? .synthetic
    }
}

extension WorldRenderControls: FrameStatsProviding, SceneStatsProviding {
    public var frameStatsSnapshot: FrameStatsSnapshot {
        renderer?.frameStats.snapshot() ?? .empty
    }

    public var sceneStatsSnapshot: SceneStatsSnapshot {
        let draw = renderer?.lastDrawStats ?? SceneDrawStats()
        return SceneStatsSnapshot(
            drawCalls: draw.drawCalls,
            drawnInstances: draw.drawnInstances,
            culledInstances: draw.culledInstances,
            residentCellCount: streamer?.residentCellCount ?? 0,
            // Process-wide, so it stays meaningful with no renderer.
            memoryFootprintMB: MemoryFootprint.physFootprintMB()
        )
    }
}

/// Without a streamer the trigger snapshot says so, instead of zeros that would
/// read as "no cell authors a trigger".
extension WorldRenderControls: TriggerControlProviding, PhysicsControlProviding {
    public var triggerStatsSnapshot: TriggerStatsSnapshot {
        guard let streamer else { return .unavailable }
        return TriggerStatsSnapshot(
            streamerAvailable: true,
            stats: streamer.triggerStats(),
            occupiedCount: streamer.occupiedTriggers.count,
            walkModeActive: renderer?.movementMode.isPlayerControlled ?? false,
            recentTransitions: streamer.triggerLog.lines,
            recordedTransitionCount: streamer.triggerLog.recordedCount
        )
    }

    public func clearTriggerLog() {
        streamer?.triggerLog.clear()
    }

    public var dynamicBodyStatsSnapshot: DynamicBodyStatsSnapshot {
        streamer?.dynamicBodies.statsSnapshot ?? DynamicBodyStatsSnapshot()
    }

    public func setPhysicsFrozen(_ frozen: Bool) {
        streamer?.dynamicBodies.isFrozen = frozen
    }

    public func resetDynamicBodies() {
        streamer?.dynamicBodies.reset()
    }
}
