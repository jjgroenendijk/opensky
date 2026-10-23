// The renderer and streamer controls behind agent control: shadows, terrain
// LOD, render debug, camera, frame and scene stats, triggers, and physics.
// Without a renderer or a streamer every read degrades to a stated default.

import OpenSkyDiagnostics
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyTerrain

/// What `WorldRenderControls` reads from the app.
@MainActor
public protocol RenderControlWorld: AnyObject {
    /// Nil when the GPU lacks Metal 4.
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    /// Nil without game data.
    var streamer: CellStreamer? { get }
    func refocusGameView()
}

@MainActor
public final class WorldRenderControls {
    weak let world: (any RenderControlWorld)?
    /// The time-of-day control scrubs the clock through the runtime state, so
    /// the scrub is journalled.
    let runtimeState: RuntimeStateCoordinator

    var renderer: Renderer? {
        world?.renderer
    }

    var gameSession: GameSession? {
        world?.gameSession
    }

    var streamer: CellStreamer? {
        world?.streamer
    }

    public init(runtimeState: RuntimeStateCoordinator, world: any RenderControlWorld) {
        self.runtimeState = runtimeState
        self.world = world
    }
}

extension WorldRenderControls {
    public var shadowsActive: Bool {
        renderer?.shadowRenders ?? false
    }

    public func refocusGameView() {
        world?.refocusGameView()
    }
}

extension WorldRenderControls {
    public var renderDebugMode: RenderDebugMode {
        get { renderer?.renderDebug.mode ?? .off }
        set { renderer?.renderDebug.mode = newValue }
    }

    public var renderDebugLayers: RenderLayer {
        get { renderer?.renderDebug.layers ?? .all }
        set { renderer?.renderDebug.layers = newValue }
    }
}

extension WorldRenderControls {
    public var renderPerformanceSnapshot: RenderPerformanceSnapshot? {
        guard let renderer else { return nil }
        let camera = renderer.lastDrawStats
        let shadow = renderer.lastShadowDrawStats
        var snapshot = RenderPerformanceSnapshot(
            renderTargets: renderer.renderTargetMemory(),
            pipelineCache: renderer.pipelineCache.stats,
            cpuCulling: CullCounts(
                cameraVisible: camera.drawnInstances,
                cameraCulled: camera.culledInstances,
                shadowVisible: shadow.drawnInstances,
                shadowCulled: shadow.culledInstances
            ),
            gpuCulling: renderer.lastGPUCullCounts
        )
        snapshot.upscaling = renderer.upscale.status
        snapshot.frameInterpolation = renderer.frameInterpolationStatus
        snapshot.meshShaderGrass = renderer.meshShaderGrassStatus
        snapshot.roomCulling = renderer.roomCullingReadout
        snapshot.textureStreaming = renderer.textureStreaming.stats
        snapshot.rayTracing = renderer.rayTracedShadows.availability
        snapshot.rayTracedShadows = renderer.rayTracedShadows.stats
        return snapshot
    }
}

extension WorldRenderControls {
    public var cameraPose: CameraPoseSnapshot {
        guard let gameSession else { return .unavailable }
        let camera = gameSession.freeFlyCamera
        return CameraPoseSnapshot(
            position: camera.position,
            yaw: camera.yaw,
            pitch: camera.pitch,
            cell: CellGridManager.cellCoordinate(for: camera.position),
            movementMode: gameSession.movementMode
        )
    }

    public var movementMode: CameraMovementMode {
        get { gameSession?.movementMode ?? .fly }
        set { gameSession?.setMovementMode(newValue) }
    }
}

extension WorldRenderControls {
    public var frameStatsSnapshot: FrameStatsSnapshot {
        renderer?.frameStats.snapshot() ?? .empty
    }

    public var sceneStatsSnapshot: SceneStatsSnapshot {
        let draw = renderer?.combinedDrawStats() ?? SceneDrawStats()
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
extension WorldRenderControls {
    public var triggerStatsSnapshot: TriggerStatsSnapshot {
        guard let streamer else { return .unavailable }
        var snapshot = TriggerStatsSnapshot(
            streamerAvailable: true,
            stats: streamer.triggerStats(),
            occupiedCount: streamer.occupiedTriggers.count,
            walkModeActive: gameSession?.movementMode.isPlayerControlled ?? false,
            recentTransitions: streamer.triggerLog.lines,
            recordedTransitionCount: streamer.triggerLog.recordedCount
        )
        snapshot.automaticDoors = streamer.automaticDoorReadout
        return snapshot
    }

    public var dynamicBodyStatsSnapshot: DynamicBodyStatsSnapshot {
        streamer?.dynamicBodies.statsSnapshot ?? DynamicBodyStatsSnapshot()
    }
}
