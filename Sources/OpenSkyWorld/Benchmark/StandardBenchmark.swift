// The setup of the shared benchmark: a headless renderer and a fresh cell
// builder over the install. `openskycli benchmark` and the Diagnostics page
// both run it, so a problem report shows the number a developer measures.

import Foundation
import Metal
import MetalKit
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyPlayer
import OpenSkyRendering

@MainActor
public enum StandardBenchmark {
    /// A session whose renderer draws offscreen at the plan's size, with the saved pipelines.
    public static func makeSession(
        device: MTLDevice, plan: PerformanceBenchmarkPlan, store: PlayerSettingsStore
    ) throws -> GameSession {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: plan.frameWidth, height: plan.frameHeight),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try GameSession(
            view: view,
            scene: RenderScene(instances: []),
            movementConfiguration: .synthetic,
            pipelineCache: PipelineCache.fromSettings(device: device, store: store)
        )
    }

    /// A builder with empty caches. A `recorder` gets every file read and asset phase.
    public static func makeBuilder(
        root: GameDataRoot, loadOrder: ActiveLoadOrder, files: any GameFileSource,
        device: MTLDevice, recorder: LoadPhaseRecorder?
    ) throws -> CellSceneBuilder {
        try makeBuilder(
            loadOrder: loadOrder, files: files, device: device, recorder: recorder,
            terrainLOD: terrainLODStore(root: root, settings: PlayerSettingsFile.savedData())
        )
    }

    /// The same builder off the main actor, with the terrain LOD settings read by the caller.
    nonisolated public static func makeBuilder(
        loadOrder: ActiveLoadOrder, files: any GameFileSource, device: MTLDevice,
        recorder: LoadPhaseRecorder?, terrainLOD: TerrainLODConfigurationStore
    ) throws -> CellSceneBuilder {
        let fileSystem: any GameFileSource = recorder
            .map { PhaseTimedFileSource(base: files, recorder: $0) } ?? files
        let textures = try TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        let builder = CellSceneBuilder(
            file: loadOrder.baseFile,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem,
            plugins: loadOrder.files,
            terrainLODConfigurationStore: terrainLOD
        )
        builder.loadPhases = recorder
        return builder
    }

    nonisolated public static func terrainLODStore(
        root: GameDataRoot, settings: Data?
    ) -> TerrainLODConfigurationStore {
        TerrainLODConfigurationStore(snapshot: TerrainLODSettings.load(
            root: root,
            settings: settings
        ))
    }

    /// The benchmark with the saved settings and no options, as the Diagnostics page runs it.
    public static func run(
        root: GameDataRoot,
        device: MTLDevice
    ) throws -> PerformanceBenchmarkResult {
        let store = PlayerSettingsStore(persistence: try? PlayerSettingsFile.defaultFile())
        let plan = PerformanceBenchmarkPlan.standard
        let gameSession = try makeSession(device: device, plan: plan, store: store)
        let loadOrder = try ActiveLoadOrder.open(root: root)
        return try PerformanceBenchmark.run(
            plan: plan, machine: .current(gpu: device.name), gameSession: gameSession
        ) { recorder in
            try makeBuilder(
                root: root, loadOrder: loadOrder, files: VirtualFileSystem(root: root),
                device: device, recorder: recorder
            )
        }
    }
}
