// `bench`: sustained one-cell render + scripted flight/walk production gates.

import Foundation
import Metal
import MetalKit
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld

enum BenchCommand {
    /// 30 fps -> 33.33 ms per frame.
    private static let defaultBudgetMS = 1000.0 / 30.0
    #if DEBUG
        private static let isDebugBuild = true
    #else
        private static let isDebugBuild = false
    #endif
    private static let defaultFrames = 360 // 3 full FrameStats windows
    private static let defaultFlyMaxFrames = 36000
    private static let defaultFootprintCapMB = 1024.0
    private static let defaultCollisionBuildBudgetMS = 750.0
    /// Debug budget for cold rig, clip, body, and FaceGen loads, with LZ4
    /// independent-block decoding. Measured p95: 2224 ms on the Whiterun fly path.
    private static let defaultActorBuildBudgetMS = 3000.0
    /// CPU-only sample/compose/palette refresh; leaves wide Debug headroom.
    private static let defaultAnimationUpdateBudgetMS = 4.0
    /// CPU cost of `encodeShadowPass`: cascade fit, caster culling, ring writes,
    /// and depth encode. Debug p95 at 640x360 is 13.20 ms; 14 ms keeps headroom
    /// below half the 30 fps frame.
    private static let defaultShadowUpdateBudgetMS = 14.0
    /// CPU cost of the per-frame audio update: listener pose, `WorldAudioEngine`
    /// tick, and music director. Measured floor p95 0.014 ms; 0.5 ms allows the
    /// 8-source cap and trips only work that scales with something else.
    private static let defaultAudioUpdateBudgetMS = 0.5
    /// CPU cost of the per-frame Papyrus callback with an empty VM tick.
    /// Measured p95 0.035 ms; 0.5 ms leaves room for event bursts and is about
    /// 1.5% of a 30 fps frame.
    private static let defaultScriptUpdateBudgetMS = 0.5

    private struct Options {
        let worldspace: String
        let start: CellCoordinate
        let size: (width: Int, height: Int)
        let frames: Int
        let budgetMS: Double
        let walkFrameBudget: WalkBenchmarkFrameBudget
        let flyPath: Bool
        let walkPath: Bool
        let output: String?
        let maxFrames: Int
        let footprintCapMB: Double
        let collisionBuildBudgetMS: Double
        let actorBuildBudgetMS: Double
        let animationUpdateBudgetMS: Double
        let shadowUpdateBudgetMS: Double
        let audioUpdateBudgetMS: Double
        let scriptUpdateBudgetMS: Double
    }

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let assets = try AssetLoadOptions(scanner: &scanner, context: context)
        let options = try parseOptions(scanner: &scanner)
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }

        if options.flyPath {
            try runFlyPath(context: context, device: device, options: options, assets: assets)
        } else if options.walkPath {
            try runWalkPath(context: context, device: device, options: options, assets: assets)
        } else {
            try runSustained(context: context, device: device, options: options)
        }
    }

    private static func runSustained(
        context: CLIContext,
        device: MTLDevice,
        options: Options
    ) throws {
        let cellScene = try RenderCommand.buildScene(
            context: context,
            device: device,
            worldspace: options.worldspace,
            gridX: options.start.x,
            gridY: options.start.y
        )
        print(cellScene.summary.summaryLine)
        guard let bounds = cellScene.bounds else {
            throw CLIError.failure("nothing drew — no bounds to frame a camera on")
        }

        // Headless MTKView carries pixel-format config only (render command
        // pattern); the offscreen path never touches its drawable.
        let view = MTKView(
            frame: CGRect(
                x: 0, y: 0,
                width: options.size.width,
                height: options.size.height
            ),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: cellScene.renderScene,
            camera: SceneCamera.framing(bounds: bounds),
            movementConfiguration: .synthetic
        )
        let result = try renderer.renderOffscreenSustained(
            width: options.size.width,
            height: options.size.height,
            frames: options.frames
        )
        report(
            result: result,
            size: options.size,
            frames: options.frames,
            budget: options.budgetMS
        )
        let avg = result.averageMS
        let p95 = result.percentileMS(95)
        guard avg <= options.budgetMS, p95 <= options.budgetMS else {
            throw CLIError.failure(String(
                format: "frame time over budget: avg %.2f ms / p95 %.2f ms vs %.2f ms",
                avg, p95, options.budgetMS
            ))
        }
        print(String(
            format: "[ OK ] sustained frame time within %.2f ms budget",
            options.budgetMS
        ))
    }

    private static func runFlyPath(
        context: CLIContext,
        device: MTLDevice,
        options: Options,
        assets: AssetLoadOptions
    ) throws {
        let builder = try RenderCommand.makeBuilder(
            context: context,
            device: device,
            assets: assets
        )
        defer { try? assets.report() }
        let weather = WeatherSystem(file: builder.file, worldspaceEditorID: options.worldspace)
        let provider = BuilderCellSceneProvider(
            builder: builder,
            worldspaceEditorID: options.worldspace
        )
        let renderer = try makeStreamRenderer(device: device, size: options.size)
        wireBenchScriptRuntime(to: renderer)
        let result = try CellStreamingFlyBenchmark.run(
            renderer: renderer,
            provider: provider,
            weather: weather,
            configuration: CellStreamingFlyBenchmarkConfiguration(
                start: options.start,
                size: options.size,
                maxFrames: options.maxFrames,
                footprintCapMB: options.footprintCapMB,
                collisionBuildBudgetMS: options.collisionBuildBudgetMS,
                actorBuildBudgetMS: options.actorBuildBudgetMS,
                animationUpdateBudgetMS: options.animationUpdateBudgetMS,
                shadowUpdateBudgetMS: options.shadowUpdateBudgetMS,
                audioUpdateBudgetMS: options.audioUpdateBudgetMS,
                scriptUpdateBudgetMS: options.scriptUpdateBudgetMS
            )
        )
        reportFlyPath(
            result: result,
            size: options.size,
            budget: options.budgetMS
        )
        guard
            result.render.averageMS <= options.budgetMS,
            result.render.percentileMS(95) <= options.budgetMS
        else {
            throw CLIError.failure(String(
                format: "stream frame time over budget: avg %.2f / p95 %.2f vs %.2f ms",
                result.render.averageMS,
                result.render.percentileMS(95),
                options.budgetMS
            ))
        }
        print("[ OK ] cross-cell stream settled, unloaded safely, built each cell once")
    }

    private static func runWalkPath(
        context: CLIContext,
        device: MTLDevice,
        options: Options,
        assets: AssetLoadOptions
    ) throws {
        let builder = try RenderCommand.makeBuilder(
            context: context,
            device: device,
            assets: assets
        )
        defer { try? assets.report() }
        let provider = BuilderCellSceneProvider(
            builder: builder,
            worldspaceEditorID: options.worldspace
        )
        let renderer = try makeStreamRenderer(device: device, size: options.size)
        let result = try CellStreamingWalkBenchmark.run(
            renderer: renderer,
            provider: provider,
            configuration: CellStreamingWalkBenchmarkConfiguration(
                size: options.size,
                maxFrames: options.maxFrames
            )
        )
        reportWalkPath(
            result: result,
            size: options.size,
            frameBudget: options.walkFrameBudget,
            audioBudget: options.audioUpdateBudgetMS
        )
        guard options.walkFrameBudget.contains(result.physicsRender) else {
            throw CLIError.failure(String(
                format: "physics frame time over budget: avg %.2f vs %.2f ms / "
                    + "p95 %.2f vs %.2f ms",
                result.physicsRender.averageMS,
                options.walkFrameBudget.averageMS,
                result.physicsRender.percentileMS(95),
                options.walkFrameBudget.percentile95MS
            ))
        }
        try checkAudioBudget(
            render: result.physicsRender,
            budget: options.audioUpdateBudgetMS
        )
        if let output = options.output {
            let texture = try renderer.renderOffscreen(
                width: options.size.width,
                height: options.size.height
            )
            let url = URL(fileURLWithPath: output)
            try FrameScreenshot.write(texture: texture, to: url)
            print("[INFO] wrote walk-path frame -> \(url.path(percentEncoded: false))")
        }
        print("[ OK ] walk path crossed terrain, stairs, interior, paired return")
    }
}

extension BenchCommand {
    /// A paused offscreen renderer with the bench audio engine, for the stream routes.
    private static func makeStreamRenderer(
        device: MTLDevice, size: (width: Int, height: Int)
    ) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: size.width, height: size.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: RenderScene(instances: []),
            movementConfiguration: .synthetic
        )
        renderer.worldAudio = benchAudioEngine()
        return renderer
    }

    /// Attaches an empty VM so the fly path measures the fixed engine-loop
    /// floor. The callback retains the runtime for the complete render run.
    private static func wireBenchScriptRuntime(to renderer: Renderer) {
        let runtime = PapyrusWorldRuntime(runtime: PapyrusRuntime(
            files: [], nativeDispatch: PapyrusNativeRegistry.standard
        ))
        renderer.onWorldUpdate = { [runtime, weak renderer] delta in
            _ = runtime.advance(delta: delta, gameClock: renderer?.gameClock)
        }
    }

    /// A world audio engine attached to the benchmark renderer so the per-frame
    /// audio update actually runs and can be measured. It is left disabled, so
    /// no output device is opened and nothing plays: the benchmark measures the
    /// fixed per-frame cost of the listener push, the engine tick and the music
    /// director, which is the part of the audio subsystem that runs every frame
    /// regardless of how many sources are live.
    private static func benchAudioEngine() -> WorldAudioEngine {
        WorldAudioEngine()
    }

    /// Shared audio-budget gate for the walk path. The fly path enforces the
    /// same numbers inside `CellStreamingFlyBenchmark`, which owns its own
    /// reason-tagged error type.
    private static func checkAudioBudget(
        render: OffscreenBenchResult,
        budget: Double
    ) throws {
        guard
            render.audioUpdateAverageMS <= budget,
            render.audioUpdatePercentileMS(95) <= budget
        else {
            throw CLIError.failure(String(
                format: "audio update over budget: avg %.2f / p95 %.2f vs %.2f ms",
                render.audioUpdateAverageMS,
                render.audioUpdatePercentileMS(95),
                budget
            ))
        }
    }

    private static func parseOptions(scanner: inout ArgumentScanner) throws -> Options {
        let worldspace = try scanner.option("--worldspace")
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = try RenderCommand.int32(scanner.option("--x"), name: "--x")
            ?? FirstRenderCell.gridX
        let gridY = try RenderCommand.int32(scanner.option("--y"), name: "--y")
            ?? FirstRenderCell.gridY
        let flyPath = scanner.flag("--fly-path")
        let walkPath = scanner.flag("--walk-path")
        guard !flyPath || !walkPath else {
            throw CLIError.usage("choose one of --fly-path or --walk-path")
        }
        let pathSpecific = try BenchPathSpecificOptions(scanner: &scanner, walkPath: walkPath)
        let budgetOption = try scanner.option("--budget-ms")
        let budgetMS = try positiveDouble(
            budgetOption,
            flag: "--budget-ms",
            fallback: defaultBudgetMS
        )
        let options = try Options(
            worldspace: worldspace,
            start: CellCoordinate(x: gridX, y: gridY),
            size: RenderCommand.parseSize(scanner.option("--size")),
            frames: frameCount(pathSpecific.frames),
            budgetMS: budgetMS,
            walkFrameBudget: walkFrameBudget(
                budgetMS: budgetMS,
                wasExplicit: budgetOption != nil
            ),
            flyPath: flyPath,
            walkPath: walkPath,
            output: scanner.option("--out"),
            maxFrames: maxFrameCount(scanner.option("--max-frames")),
            footprintCapMB: positiveDouble(
                pathSpecific.footprintCapMB,
                flag: "--footprint-cap-mb", fallback: defaultFootprintCapMB
            ),
            collisionBuildBudgetMS: positiveDouble(
                pathSpecific.collisionBuildBudgetMS,
                flag: "--collision-build-budget-ms", fallback: defaultCollisionBuildBudgetMS
            ),
            actorBuildBudgetMS: positiveDouble(
                pathSpecific.actorBuildBudgetMS,
                flag: "--actor-build-budget-ms", fallback: defaultActorBuildBudgetMS
            ),
            animationUpdateBudgetMS: positiveDouble(
                pathSpecific.animationUpdateBudgetMS,
                flag: "--animation-budget-ms", fallback: defaultAnimationUpdateBudgetMS
            ),
            shadowUpdateBudgetMS: positiveDouble(
                pathSpecific.shadowUpdateBudgetMS,
                flag: "--shadow-budget-ms", fallback: defaultShadowUpdateBudgetMS
            ),
            audioUpdateBudgetMS: audioUpdateBudget(scanner.option("--audio-budget-ms")),
            scriptUpdateBudgetMS: scriptUpdateBudget(pathSpecific.scriptUpdateBudgetMS)
        )
        try validateCombination(options)
        try scanner.finish()
        return options
    }

    private static func walkFrameBudget(
        budgetMS: Double,
        wasExplicit: Bool
    ) -> WalkBenchmarkFrameBudget {
        if wasExplicit {
            return WalkBenchmarkFrameBudget.strict(frameIntervalMS: budgetMS)
        }
        return WalkBenchmarkFrameBudget.buildDefault(
            frameIntervalMS: budgetMS,
            debugBuild: isDebugBuild
        )
    }

    private static func scriptUpdateBudget(_ value: String?) throws -> Double {
        try positiveDouble(
            value,
            flag: "--script-budget-ms",
            fallback: defaultScriptUpdateBudgetMS
        )
    }

    private static func audioUpdateBudget(_ value: String?) throws -> Double {
        try positiveDouble(
            value,
            flag: "--audio-budget-ms",
            fallback: defaultAudioUpdateBudgetMS
        )
    }

    /// Flag combinations no single option check can catch.
    private static func validateCombination(_ options: Options) throws {
        if options.output != nil, !options.walkPath {
            throw CLIError.usage("--out is supported only with --walk-path")
        }
        if options.walkPath {
            guard
                options.worldspace == FirstRenderCell.worldspaceEditorID,
                options.start == WalkPathRoute.startCell
            else {
                throw CLIError.usage("--walk-path uses fixed Tamriel start cell (6,-2)")
            }
        }
    }

    private static func frameCount(_ value: String?) throws -> Int {
        guard let value else { return defaultFrames }
        guard let frames = Int(value), (1 ... 100_000).contains(frames) else {
            throw CLIError.usage("--frames expects an integer (1-100000), got \(value)")
        }
        return frames
    }

    private static func maxFrameCount(_ value: String?) throws -> Int {
        guard let value else { return defaultFlyMaxFrames }
        guard let frames = Int(value), (1 ... 100_000).contains(frames) else {
            throw CLIError.usage("--max-frames expects an integer (1-100000), got \(value)")
        }
        return frames
    }

    /// Shared positive-number option parser for every millisecond budget + the
    /// footprint cap: absent -> `fallback`, present -> a value that must parse
    /// as a Double above zero (a typo or non-positive is a usage error).
    private static func positiveDouble(
        _ value: String?,
        flag: String,
        fallback: Double
    ) throws -> Double {
        guard let value else { return fallback }
        guard let parsed = Double(value), parsed > 0 else {
            throw CLIError.usage("\(flag) expects a positive number, got \(value)")
        }
        return parsed
    }
}
