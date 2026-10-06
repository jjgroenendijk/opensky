// `render`: build one exterior cell scene from the install and render it
// offscreen to a PNG — the app's launch path (docs/engine/cell-scene.md)
// minus the window, using Renderer.renderOffscreen for a deterministic
// frame. Output goes wherever --out points; engine output (our pixels), not
// extracted game data.

import Foundation
import Metal
import MetalKit
import OpenSkyAssetCache
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld
import simd

/// The cells `render` built, their bounds, and the merged scene with distant LOD.
struct RenderSceneBuild {
    let cellScenes: [CellScene]
    let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)
    let scene: RenderScene
}

enum RenderCommand {
    /// Production streaming footprint: target plus two rings (5x5).
    private static let neighborOffsets: [(dx: Int32, dy: Int32)] = (-2 ... 2).flatMap { y in
        (-2 ... 2).map { x in (Int32(x), Int32(y)) }
    }

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let options = try parseOptions(&scanner)

        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }

        // One shared builder so the 5x5 + LOD dedup cache residency.
        let builder = try makeBuilder(context: context, device: device)
        let built = try buildRenderScene(builder: builder, options: options)
        let (cellScenes, scene) = (built.cellScenes, built.scene)
        let detection = options.detectionOverlay
            ? warmedDetection(cellScenes, context: context)
            : nil
        let membrane = options.effects.membrane == nil ? nil : MembraneSubject(scene: scene)
        let camera = membrane?.camera ?? SceneCamera.framing(bounds: built.bounds)
        let render = try renderOffscreen(
            device: device,
            scene: scene,
            camera: zoomed(camera, zoom: options.zoom),
            size: options.size,
            timeOfDay: options.timeOfDay,
            uiScene: options.uiSample ? .labSample : .empty,
            navigationOverlayGraph: options.navmeshOverlay
                ? makeNavigationGraph(cellScenes) : nil,
            detectionOverlay: detection?.runtime,
            frames: options.effects.frames,
            configure: { renderer in
                try applyEffects(options.effects, to: renderer, scene: EffectCaptureScene(
                    context: context, file: builder.file,
                    worldspace: options.worldspace, membraneOwner: membrane?.owner
                ))
            },
            inspect: printEffectState
        )
        if let detection {
            printDetectionStats(detection.runtime)
        }
        try report(
            render,
            scene: scene,
            output: options.output,
            overlays: (
                ui: options.uiSample,
                world: options.navmeshOverlay || options.detectionOverlay
            )
        )
    }

    private static func buildRenderScene(
        builder: CellSceneBuilder, options: Options
    ) throws -> RenderSceneBuild {
        let cellScenes = buildCellScenes(
            builder: builder,
            worldspace: options.worldspace,
            gridX: options.gridX,
            gridY: options.gridY,
            neighbors: options.neighbors
        )
        guard !cellScenes.isEmpty else {
            throw CLIError.failure("no cells built")
        }
        guard let bounds = unionBounds(cellScenes) else {
            throw CLIError.failure("nothing drew — no bounds to frame a camera on")
        }
        let scene = try sceneWithLOD(
            builder: builder,
            cellScenes: cellScenes,
            worldspace: options.worldspace,
            center: CellCoordinate(x: options.gridX, y: options.gridY)
        )
        return RenderSceneBuild(cellScenes: cellScenes, bounds: bounds, scene: scene)
    }

    private static func buildCellScenes(
        builder: CellSceneBuilder,
        worldspace: String,
        gridX: Int32,
        gridY: Int32,
        neighbors: Bool
    ) -> [CellScene] {
        let offsets = neighbors ? neighborOffsets : [(dx: 0, dy: 0)]
        return offsets.compactMap { offset in
            let x = gridX + offset.dx
            let y = gridY + offset.dy
            do {
                let scene = try builder.buildScene(
                    worldspaceEditorID: worldspace,
                    gridX: x,
                    gridY: y
                )
                print(scene.summary.summaryLine)
                return scene
            } catch {
                printError("[WARN] cell (\(x),\(y)) skipped: \(String(describing: error))")
                return nil
            }
        }
    }

    private static func makeNavigationGraph(_ scenes: [CellScene]) -> RuntimeNavigationGraph {
        var graph = RuntimeNavigationGraph()
        for scene in scenes {
            guard let location = scene.location else { continue }
            graph.setCell(location, scene: scene)
        }
        return graph
    }

    private static func sceneWithLOD(
        builder: CellSceneBuilder,
        cellScenes: [CellScene],
        worldspace: String,
        center: CellCoordinate
    ) throws -> RenderScene {
        // Hide only the cells actually built: hiding the whole 5x5 while
        // rendering a single cell (no --neighbors) left a 24-cell ring with
        // neither full terrain nor LOD — sky showed through the gap.
        let built = Set(cellScenes.compactMap { scene -> CellCoordinate? in
            if case let .exterior(coordinate) = scene.location {
                return coordinate
            }
            return nil
        })
        let lod = try builder.buildDistantLOD(
            worldspaceEditorID: worldspace,
            center: center,
            hiddenCells: built
        )
        if let lod {
            print("[INFO] distant LOD: \(lod.blockCount) blocks, "
                + "\(lod.missingBlockCount) unavailable, \(lod.treeBlockCount) tree blocks, "
                + "\(lod.missingTreeBlockCount) unavailable tree blocks, "
                + "\(lod.treeInstanceCount) trees")
        }
        var scenes = cellScenes.map(\.renderScene)
        if let lod {
            scenes.append(lod.renderScene)
        }
        return RenderScene(merging: scenes)
    }

    /// Enclosing AABB over every built cell's bounds; nil input/all-nil
    /// bounds -> nil (nothing drew anywhere).
    private static func unionBounds(
        _ cellScenes: [CellScene]
    ) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        var result: (min: SIMD3<Float>, max: SIMD3<Float>)?
        for bounds in cellScenes.compactMap(\.bounds) {
            guard let existing = result else {
                result = bounds
                continue
            }
            result = (
                min: simd_min(existing.min, bounds.min),
                max: simd_max(existing.max, bounds.max)
            )
        }
        return result
    }

    /// Shared with BenchCommand (same scene-build + option surface).
    static func int32(_ value: String?, name: String) throws -> Int32? {
        guard let value else { return nil }
        guard let parsed = Int32(value) else {
            throw CLIError.usage("\(name) expects an integer, got \(value)")
        }
        return parsed
    }

    /// "--size 1280x720" -> (1280, 720); bounded so a typo cannot ask the
    /// GPU for a texture it can never allocate.
    static func parseSize(_ value: String?) throws -> (width: Int, height: Int) {
        guard let value else { return (1280, 720) }
        let parts = value.lowercased().split(separator: "x")
        guard
            parts.count == 2,
            let width = Int(parts[0]), let height = Int(parts[1]),
            (1 ... 8192).contains(width), (1 ... 8192).contains(height)
        else {
            throw CLIError.usage("--size expects WxH (each 1-8192), got \(value)")
        }
        return (width, height)
    }

    /// Shared with BenchCommand: one cell, fresh libraries.
    static func buildScene(
        context: CLIContext,
        device: MTLDevice,
        worldspace: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> CellScene {
        let builder = try makeBuilder(context: context, device: device)
        do {
            return try builder.buildScene(
                worldspaceEditorID: worldspace,
                gridX: gridX,
                gridY: gridY
            )
        } catch let error as CellSceneError {
            throw CLIError.failure(String(describing: error))
        }
    }

    /// One VFS + ESM + MeshLibrary/TextureLibrary/CellSceneBuilder trio.
    /// Reusing one instance across multiple `buildScene` calls (the
    /// `--neighbors` grid) shares the STAT index and dedups mesh/texture
    /// residency across cells — `--neighbors` calls this once, `buildScene`
    /// calls it once per invocation. A `recorder` gets every file read and asset phase.
    static func makeBuilder(
        context: CLIContext,
        device: MTLDevice,
        recorder: LoadPhaseRecorder? = nil,
        assets: AssetLoadOptions? = nil
    ) throws -> CellSceneBuilder {
        let vfs = context.makeFileSystem()
        var files: any GameFileSource = vfs
        if let looseFolder = assets?.looseFolder {
            files = FolderOverlayFileSource(base: vfs, folder: looseFolder)
        }
        let fileSystem: any GameFileSource = recorder
            .map { PhaseTimedFileSource(base: files, recorder: $0) } ?? files
        let file = try context.loadSkyrimESM()
        let textures = try TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        let builder = CellSceneBuilder(
            file: file,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem,
            terrainLODConfigurationStore: context.makeTerrainLODConfigurationStore()
        )
        builder.loadPhases = recorder
        try assets?.configure(builder, device: device)
        return builder
    }
}
