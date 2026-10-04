// The shared performance benchmark: a cold and a warm load of fixed cells, then
// frame time on a fixed view. Callers own the data root and the renderer; this
// driver owns the steps. See docs/tools/benchmark.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

nonisolated public enum PerformanceBenchmarkError: LocalizedError {
    /// No built exterior cell has terrain under the view's eye.
    case noGroundAtView(x: Float, y: Float)

    public var errorDescription: String? {
        switch self {
        case let .noGroundAtView(x, y):
            "benchmark view has no built terrain under (\(x), \(y))"
        }
    }
}

@MainActor
public enum PerformanceBenchmark {
    /// - Parameters:
    ///   - makeBuilder: returns a builder with empty caches whose file source and
    ///     `loadPhases` report into the given recorder. Called once, for the cold pass.
    ///   - renderer: an offscreen-capable renderer; its scene and camera are replaced.
    public static func run(
        plan: PerformanceBenchmarkPlan = .standard,
        machine: BenchmarkMachine,
        renderer: Renderer,
        makeBuilder: (LoadPhaseRecorder) throws -> CellSceneBuilder
    ) throws -> PerformanceBenchmarkResult {
        let startedAt = Date()
        let recorder = LoadPhaseRecorder()

        let coldStart = nanoseconds()
        let builder = try makeBuilder(recorder)
        let setupMS = milliseconds(since: coldStart)
        let cold = loadPass(plan: plan, builder: builder)
        let coldMS = milliseconds(since: coldStart)
        let coldLoad = BenchmarkLoadPass(
            totalMS: coldMS,
            setupMS: setupMS,
            phases: recorder.snapshot().completed(totalMS: coldMS),
            cells: cold.cells
        )

        recorder.reset()
        let warmStart = nanoseconds()
        let warm = loadPass(plan: plan, builder: builder)
        let warmMS = milliseconds(since: warmStart)
        let warmLoad = BenchmarkLoadPass(
            totalMS: warmMS,
            setupMS: 0,
            phases: recorder.snapshot().completed(totalMS: warmMS),
            cells: warm.cells
        )

        return try PerformanceBenchmarkResult(
            startedAt: startedAt,
            machine: machine,
            buildConfiguration: .current,
            plan: plan,
            coldLoad: coldLoad,
            warmLoad: warmLoad,
            frameTime: frameTime(plan: plan, loaded: warm, renderer: renderer)
        )
    }

    private struct LoadPassOutput {
        var cells: [BenchmarkCellLoad] = []
        var exteriorScenes: [CellScene] = []
        var distantLOD: RenderScene?
    }

    private static func loadPass(
        plan: PerformanceBenchmarkPlan,
        builder: CellSceneBuilder
    ) -> LoadPassOutput {
        var output = LoadPassOutput()
        for cell in plan.exteriorCells {
            let label = "\(plan.worldspace) (\(cell.x),\(cell.y))"
            let built = timedBuild(label: label) {
                try builder.buildScene(
                    worldspaceEditorID: plan.worldspace, gridX: cell.x, gridY: cell.y
                )
            }
            output.cells.append(built.load)
            output.exteriorScenes += built.value.map { [$0] } ?? []
        }
        let lod = timedBuild(label: "distant LOD") {
            try builder.buildDistantLOD(
                worldspaceEditorID: plan.worldspace,
                center: CellCoordinate(x: plan.centerCell.x, y: plan.centerCell.y),
                hiddenCells: Set(plan.exteriorCells.map { CellCoordinate(x: $0.x, y: $0.y) })
            )
        }
        output.cells.append(lod.load)
        output.distantLOD = lod.value??.renderScene
        for formID in plan.interiorCellFormIDs {
            let label = "interior " + String(format: "%08X", formID)
            let built = timedBuild(label: label) {
                try builder.buildInteriorScene(cellFormID: FormID(formID))
            }
            output.cells.append(built.load)
        }
        return output
    }

    private static func timedBuild<T>(
        label: String,
        _ build: () throws -> T
    ) -> (load: BenchmarkCellLoad, value: T?) {
        let started = nanoseconds()
        do {
            let value = try build()
            return (BenchmarkCellLoad(label: label, totalMS: milliseconds(since: started)), value)
        } catch {
            let load = BenchmarkCellLoad(
                label: label,
                totalMS: milliseconds(since: started),
                error: String(describing: error)
            )
            return (load, nil)
        }
    }

    private static func frameTime(
        plan: PerformanceBenchmarkPlan,
        loaded: LoadPassOutput,
        renderer: Renderer
    ) throws -> BenchmarkFrameTime {
        let view = plan.view
        let from = SIMD2(view.fromX, view.fromY)
        guard
            let ground = loaded.exteriorScenes.lazy
                .compactMap({ $0.terrainHeightField?.sample(at: from) }).first
        else {
            throw PerformanceBenchmarkError.noGroundAtView(x: view.fromX, y: view.fromY)
        }
        let eyeZ = ground.height + view.eyeHeight
        var scenes = loaded.exteriorScenes.map(\.renderScene)
        if let lod = loaded.distantLOD {
            scenes.append(lod)
        }
        try renderer.setScene(
            RenderScene(merging: scenes),
            camera: SceneCamera(
                eye: SIMD3(from, eyeZ),
                target: SIMD3(view.towardX, view.towardY, eyeZ),
                sunDirection: DemoScene.sunDirection,
                sunColor: DemoScene.sunColor,
                ambientColor: DemoScene.ambientColor
            )
        )
        _ = try renderer.renderOffscreenSustained(
            width: plan.frameWidth, height: plan.frameHeight, frames: plan.warmupFrames
        )
        let measured = try renderer.renderOffscreenSustained(
            width: plan.frameWidth, height: plan.frameHeight, frames: plan.measuredFrames
        )
        return BenchmarkFrameTime(
            frames: measured.frameMS.count,
            averageMS: measured.averageMS,
            percentile95MS: measured.percentileMS(95),
            worstMS: measured.frameMS.max() ?? 0,
            drawCalls: renderer.lastDrawStats.drawCalls,
            drawnInstances: renderer.lastDrawStats.drawnInstances
        )
    }

    private static func nanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func milliseconds(since started: UInt64) -> Double {
        Double(nanoseconds() - started) / 1_000_000
    }
}
