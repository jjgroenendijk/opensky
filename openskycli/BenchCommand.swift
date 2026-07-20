// `bench`: sustained one-cell rendering plus scripted streaming flight/walk
// paths. All use synchronous offscreen frames + FrameStats; path modes add
// milestone-specific production gates through shared engine benchmark logic.

import Foundation
import Metal
import MetalKit

enum BenchCommand {
    /// 30 fps -> 33.33 ms per frame.
    private static let defaultBudgetMS = 1000.0 / 30.0
    private static let defaultFrames = 360 // 3 full FrameStats windows
    private static let defaultFlyMaxFrames = 36000
    private static let defaultFootprintCapMB = 1024.0
    private static let defaultCollisionBuildBudgetMS = 700.0
    /// Debug baseline 2026-07-20: p95 2165 ms over the Whiterun fly path
    /// (first-load skinned bodies + FaceGen heads dominate) -> 3000 ms
    /// keeps ~1.4x headroom, same policy as the collision 500 -> 700 revision.
    private static let defaultActorBuildBudgetMS = 3000.0

    private struct Options {
        let worldspace: String
        let start: CellCoordinate
        let size: (width: Int, height: Int)
        let frames: Int
        let budgetMS: Double
        let flyPath: Bool
        let walkPath: Bool
        let output: String?
        let maxFrames: Int
        let footprintCapMB: Double
        let collisionBuildBudgetMS: Double
        let actorBuildBudgetMS: Double
    }

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let options = try parseOptions(scanner: &scanner)
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }

        if options.flyPath {
            try runFlyPath(context: context, device: device, options: options)
        } else if options.walkPath {
            try runWalkPath(context: context, device: device, options: options)
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
            camera: SceneCamera.framing(bounds: bounds)
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
        options: Options
    ) throws {
        let builder = try RenderCommand.makeBuilder(context: context, device: device)
        let provider = BuilderCellSceneProvider(
            builder: builder,
            worldspaceEditorID: options.worldspace
        )
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
        let renderer = try Renderer(view: view, scene: RenderScene(instances: []))
        let result = try CellStreamingFlyBenchmark.run(
            renderer: renderer,
            provider: provider,
            configuration: CellStreamingFlyBenchmarkConfiguration(
                start: options.start,
                size: options.size,
                maxFrames: options.maxFrames,
                footprintCapMB: options.footprintCapMB,
                collisionBuildBudgetMS: options.collisionBuildBudgetMS,
                actorBuildBudgetMS: options.actorBuildBudgetMS
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
        options: Options
    ) throws {
        let builder = try RenderCommand.makeBuilder(context: context, device: device)
        let provider = BuilderCellSceneProvider(
            builder: builder,
            worldspaceEditorID: options.worldspace
        )
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
        let renderer = try Renderer(view: view, scene: RenderScene(instances: []))
        let result = try CellStreamingWalkBenchmark.run(
            renderer: renderer,
            provider: provider,
            configuration: CellStreamingWalkBenchmarkConfiguration(
                size: options.size,
                maxFrames: options.maxFrames,
                worldspaceEditorID: options.worldspace
            )
        )
        reportWalkPath(result: result, size: options.size, budget: options.budgetMS)
        guard
            result.physicsRender.averageMS <= options.budgetMS,
            result.physicsRender.percentileMS(95) <= options.budgetMS
        else {
            throw CLIError.failure(String(
                format: "physics frame time over budget: avg %.2f / p95 %.2f vs %.2f ms",
                result.physicsRender.averageMS,
                result.physicsRender.percentileMS(95),
                options.budgetMS
            ))
        }
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
        let options = try Options(
            worldspace: worldspace,
            start: CellCoordinate(x: gridX, y: gridY),
            size: RenderCommand.parseSize(scanner.option("--size")),
            frames: frameCount(scanner.option("--frames")),
            budgetMS: budgetMS(scanner.option("--budget-ms")),
            flyPath: flyPath,
            walkPath: walkPath,
            output: scanner.option("--out"),
            maxFrames: maxFrameCount(scanner.option("--max-frames")),
            footprintCapMB: footprintCapMB(scanner.option("--footprint-cap-mb")),
            collisionBuildBudgetMS: collisionBuildBudgetMS(
                scanner.option("--collision-build-budget-ms")
            ),
            actorBuildBudgetMS: actorBuildBudgetMS(
                scanner.option("--actor-build-budget-ms")
            )
        )
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
        try scanner.finish()
        return options
    }

    private static func reportWalkPath(
        result: CellStreamingWalkBenchmarkResult,
        size: (width: Int, height: Int),
        budget: Double
    ) {
        let render = result.physicsRender
        let avg = render.averageMS
        let fps = avg > 0 ? 1000 / avg : 0
        print(
            "[INFO] walk route: (6,-2) -> (7,-3) -> interior 00016204 -> (7,-3)"
        )
        print(String(
            format: "[INFO] %d active physics frames @ %dx%d: avg %.2f ms (%.1f fps), "
                + "p95 %.2f ms, max %.2f ms, budget %.2f ms",
            render.frameMS.count, size.width, size.height, avg, fps,
            render.percentileMS(95), render.frameMS.max() ?? 0, budget
        ))
        print(String(
            format: "[INFO] exterior stair gain %.2f; interior crossing %.2f; "
                + "final feet (%.2f, %.2f, %.2f)",
            result.exteriorStepGain,
            result.interiorDistance,
            result.finalFeetPosition.x,
            result.finalFeetPosition.y,
            result.finalFeetPosition.z
        ))
    }

    private static func reportFlyPath(
        result: CellStreamingFlyBenchmarkResult,
        size: (width: Int, height: Int),
        budget: Double
    ) {
        for summary in result.render.windowSummaries {
            print("[INFO] stats window: \(summary)")
        }
        let footprints = result.settledFootprintsMB
            .map { String(format: "%.0f", $0) }
            .joined(separator: " -> ")
        print(
            "[INFO] waypoint footprint MB: \(footprints); "
                + String(
                    format: "peak %.0f / cap %.0f",
                    result.peakFootprintMB,
                    result.footprintCapMB
                )
        )
        print(
            "[INFO] \(result.uniqueBuildCount) unique builds, "
                + "\(result.unloadedCellCount) initial cells unloaded, "
                + "\(result.finalResidentCellCount) resident, "
                + "\(result.finalVoidCellCount) void"
        )
        print(String(
            format: "[INFO] collision build: avg %.2f ms, p95 %.2f ms, max %.2f ms, "
                + "budget %.2f ms; %d shapes, %d triangles",
            result.collisionBuildAverageMS,
            result.collisionBuildP95MS,
            result.collisionBuildMaximumMS,
            result.collisionBuildBudgetMS,
            result.collisionShapeCount,
            result.collisionTriangleCount
        ))
        print(String(
            format: "[INFO] actor build: avg %.2f ms, p95 %.2f ms, max %.2f ms, "
                + "budget %.2f ms",
            result.actorBuildAverageMS,
            result.actorBuildP95MS,
            result.actorBuildMaximumMS,
            result.actorBuildBudgetMS
        ))
        print(
            "[INFO] actors: \(result.actorDiscoveredCount) discovered = "
                + "\(result.actorRenderedCount) rendered + "
                + "\(result.actorDisabledSkipCount) disabled + "
                + "\(result.actorFailureCount) failed"
        )
        print(String(
            format: "[INFO] %d stream frames @ %dx%d: avg %.2f ms, p95 %.2f ms, "
                + "max %.2f ms, budget %.2f ms",
            result.render.frameMS.count, size.width, size.height,
            result.render.averageMS, result.render.percentileMS(95),
            result.render.frameMS.max() ?? 0, budget
        ))
    }

    private static func report(
        result: OffscreenBenchResult,
        size: (width: Int, height: Int),
        frames: Int,
        budget: Double
    ) {
        for summary in result.windowSummaries {
            print("[INFO] stats window: \(summary)")
        }
        let avg = result.averageMS
        let fps = avg > 0 ? 1000 / avg : 0
        print(String(
            format: "[INFO] %d frames @ %dx%d: avg %.2f ms (%.1f fps), "
                + "p95 %.2f ms, max %.2f ms, budget %.2f ms",
            frames, size.width, size.height, avg, fps,
            result.percentileMS(95), result.frameMS.max() ?? 0, budget
        ))
    }

    private static func frameCount(_ value: String?) throws -> Int {
        guard let value else { return defaultFrames }
        guard let frames = Int(value), (1 ... 100_000).contains(frames) else {
            throw CLIError.usage("--frames expects an integer (1-100000), got \(value)")
        }
        return frames
    }

    private static func budgetMS(_ value: String?) throws -> Double {
        guard let value else { return defaultBudgetMS }
        guard let budget = Double(value), budget > 0 else {
            throw CLIError.usage("--budget-ms expects a positive number, got \(value)")
        }
        return budget
    }

    private static func maxFrameCount(_ value: String?) throws -> Int {
        guard let value else { return defaultFlyMaxFrames }
        guard let frames = Int(value), (1 ... 100_000).contains(frames) else {
            throw CLIError.usage("--max-frames expects an integer (1-100000), got \(value)")
        }
        return frames
    }

    private static func footprintCapMB(_ value: String?) throws -> Double {
        guard let value else { return defaultFootprintCapMB }
        guard let cap = Double(value), cap > 0 else {
            throw CLIError.usage("--footprint-cap-mb expects a positive number, got \(value)")
        }
        return cap
    }

    private static func collisionBuildBudgetMS(_ value: String?) throws -> Double {
        guard let value else { return defaultCollisionBuildBudgetMS }
        guard let budget = Double(value), budget > 0 else {
            throw CLIError.usage(
                "--collision-build-budget-ms expects a positive number, got \(value)"
            )
        }
        return budget
    }

    private static func actorBuildBudgetMS(_ value: String?) throws -> Double {
        guard let value else { return defaultActorBuildBudgetMS }
        guard let budget = Double(value), budget > 0 else {
            throw CLIError.usage(
                "--actor-build-budget-ms expects a positive number, got \(value)"
            )
        }
        return budget
    }
}
