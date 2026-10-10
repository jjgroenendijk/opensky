// The setup of the shared benchmark: a headless renderer and a fresh cell
// builder over the install. `openskycli benchmark` and the Diagnostics page
// both run it, so a problem report shows the number a developer measures.

import Foundation
import Metal
import MetalKit
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

@MainActor
public enum StandardBenchmark {
    /// A renderer that draws offscreen at the plan's size, with the saved pipelines.
    public static func makeRenderer(
        device: MTLDevice, plan: PerformanceBenchmarkPlan, store: PlayerSettingsStore
    ) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: plan.frameWidth, height: plan.frameHeight),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(
            view: view,
            scene: RenderScene(instances: []),
            movementConfiguration: .synthetic,
            pipelineCache: PipelineCache.fromSettings(device: device, store: store)
        )
    }

    /// A builder with empty caches. A `recorder` gets every file read and asset phase.
    public static func makeBuilder(
        root: GameDataRoot, file: ESMFile, files: any GameFileSource, device: MTLDevice,
        recorder: LoadPhaseRecorder?
    ) throws -> CellSceneBuilder {
        let fileSystem: any GameFileSource = recorder
            .map { PhaseTimedFileSource(base: files, recorder: $0) } ?? files
        let textures = try TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        let builder = CellSceneBuilder(
            file: file,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem,
            plugins: ActivePluginFiles.load(root: root, baseFile: file),
            terrainLODConfigurationStore: TerrainLODConfigurationStore(
                snapshot: TerrainLODSettings.load(
                    root: root,
                    settings: PlayerSettingsFile.savedData()
                )
            )
        )
        builder.loadPhases = recorder
        return builder
    }

    /// The benchmark with the saved settings and no options, as the Diagnostics page runs it.
    public static func run(
        root: GameDataRoot,
        device: MTLDevice
    ) throws -> PerformanceBenchmarkResult {
        let store = PlayerSettingsStore(persistence: try? PlayerSettingsFile.defaultFile())
        let plan = PerformanceBenchmarkPlan.standard
        let renderer = try makeRenderer(device: device, plan: plan, store: store)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        return try PerformanceBenchmark.run(
            plan: plan, machine: .current(gpu: device.name), renderer: renderer
        ) { recorder in
            try makeBuilder(
                root: root, file: file, files: VirtualFileSystem(root: root), device: device,
                recorder: recorder
            )
        }
    }
}
