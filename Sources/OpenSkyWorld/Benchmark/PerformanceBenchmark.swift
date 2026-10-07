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

/// Asks the benchmark to time the start of the process: its cold load, then
/// `seconds` of frames on the view before the warm load.
nonisolated public struct BenchmarkLaunchRequest: Sendable {
    public let processStart: Date
    public let seconds: Double

    public init(processStart: Date, seconds: Double = 60) {
        self.processStart = processStart
        self.seconds = seconds
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
        launch: BenchmarkLaunchRequest? = nil,
        makeBuilder: (LoadPhaseRecorder) throws -> CellSceneBuilder
    ) throws -> PerformanceBenchmarkResult {
        var memory = GPUMemoryTracker(renderer: renderer)
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
        memory.sample()
        let launchResult = try launch.map { request in
            try launchFrames(request: request, plan: plan, loaded: cold, renderer: renderer)
        }

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
        memory.sample()

        var result = try PerformanceBenchmarkResult(
            startedAt: startedAt,
            machine: machine,
            buildConfiguration: .current,
            plan: plan,
            coldLoad: coldLoad,
            warmLoad: warmLoad,
            frameTime: frameTime(plan: plan, loaded: warm, renderer: renderer, memory: &memory)
        )
        result.gpuMemory = memory.result
        result.launch = launchResult
        return result
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
                try builder.textures.batchLoads {
                    try builder.buildScene(
                        worldspaceEditorID: plan.worldspace, gridX: cell.x, gridY: cell.y
                    )
                }
            }
            output.cells.append(built.load)
            output.exteriorScenes += built.value.map { [$0] } ?? []
        }
        let lod = timedBuild(label: "distant LOD") {
            try builder.textures.batchLoads {
                try builder.buildDistantLOD(
                    worldspaceEditorID: plan.worldspace,
                    center: CellCoordinate(x: plan.centerCell.x, y: plan.centerCell.y),
                    hiddenCells: Set(plan.exteriorCells.map { CellCoordinate(x: $0.x, y: $0.y) })
                )
            }
        }
        output.cells.append(lod.load)
        output.distantLOD = lod.value??.renderScene
        for formID in plan.interiorCellFormIDs {
            let label = "interior " + String(format: "%08X", formID)
            let built = timedBuild(label: label) {
                try builder.textures
                    .batchLoads { try builder.buildInteriorScene(cellFormID: FormID(formID)) }
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
        renderer: Renderer,
        memory: inout GPUMemoryTracker
    ) throws -> BenchmarkFrameTime {
        try show(loaded: loaded, plan: plan, renderer: renderer)
        _ = try renderer.renderOffscreenSustained(
            width: plan.frameWidth, height: plan.frameHeight, frames: plan.warmupFrames
        )
        let measured = try renderer.renderOffscreenSustained(
            width: plan.frameWidth, height: plan.frameHeight, frames: plan.measuredFrames
        ) { _ in memory.sample() }
        var frameTime = BenchmarkFrameTime(
            frames: measured.frameMS.count,
            averageMS: measured.averageMS,
            percentile95MS: measured.percentileMS(95),
            worstMS: measured.frameMS.max() ?? 0,
            drawCalls: renderer.lastDrawStats.drawCalls,
            // The GPU path's count is read a few frames late; the view does not move.
            drawnInstances: renderer.combinedDrawStats().drawnInstances,
            gpuTime: BenchmarkTimeStats(milliseconds: measured.gpuMS),
            grass: BenchmarkGrass(renderer.lastGrassDrawStats)
        )
        frameTime.encodeTime = BenchmarkTimeStats(milliseconds: measured.encodeMS)
        frameTime.gpuCulling = renderer.gpuCullingEnabled
        frameTime.renderScale = renderer.renderScale.percent
        frameTime.upscaler = renderer.renderScale.isOn ? "\(renderer.upscaler)" : nil
        frameTime.frameInterpolation = renderer.isFrameInterpolationRunning
        return frameTime
    }

    /// Frames on the cold-loaded view until `request.seconds` pass after the first one.
    private static func launchFrames(
        request: BenchmarkLaunchRequest,
        plan: PerformanceBenchmarkPlan,
        loaded: LoadPassOutput,
        renderer: Renderer
    ) throws -> BenchmarkLaunch {
        try show(loaded: loaded, plan: plan, renderer: renderer)
        let started = Date()
        var firstFrameStart: UInt64?
        let render = try renderer.pumpOffscreen(
            width: plan.frameWidth,
            height: plan.frameHeight,
            maxFrames: Int(request.seconds * 1000)
        ) {
            let now = nanoseconds()
            let first = firstFrameStart ?? now
            firstFrameStart = first
            return Double(now - first) / 1e9 >= request.seconds
        }
        let firstFrameMS = render.frameMS.first ?? 0
        return BenchmarkLaunch(
            processToFirstFrameMS: started.timeIntervalSince(request.processStart) * 1000
                + firstFrameMS,
            firstFrameMS: firstFrameMS,
            seconds: request.seconds,
            frameTime: BenchmarkTimeStats(milliseconds: render.frameMS)
                ?? BenchmarkTimeStats(frames: 0, averageMS: 0, percentile95MS: 0, worstMS: 0)
        )
    }

    private static func show(
        loaded: LoadPassOutput,
        plan: PerformanceBenchmarkPlan,
        renderer: Renderer
    ) throws {
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
    }

    static func nanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func milliseconds(since started: UInt64) -> Double {
        Double(nanoseconds() - started) / 1_000_000
    }
}

/// The peak of each memory field over the samples, and the last sample.
@MainActor
struct GPUMemoryTracker {
    let renderer: Renderer
    private var peak = GPUMemoryUsage()
    private var last: GPUMemoryUsage?

    init(renderer: Renderer) {
        self.renderer = renderer
    }

    mutating func sample() {
        let usage = renderer.gpuMemoryUsage()
        peak = peak.fieldMaximum(usage)
        last = usage
    }

    var result: BenchmarkGPUMemory? {
        guard let last else { return nil }
        return BenchmarkGPUMemory(
            peak: BenchmarkGPUMemorySample(peak),
            last: BenchmarkGPUMemorySample(last)
        )
    }
}
