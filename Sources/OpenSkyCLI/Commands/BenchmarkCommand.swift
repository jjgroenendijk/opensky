// `benchmark`: the shared performance benchmark on the real install. Prints a
// summary and writes the stable JSON result (docs/tools/benchmark.md).

import Darwin
import Foundation
import Metal
import MetalKit
import OpenSkyAssetCache
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld

enum BenchmarkCommand {
    private struct Options {
        let outPath: String?
        let framePath: String?
        let plan: PerformanceBenchmarkPlan
        let launch: BenchmarkLaunchRequest?
        let route: Bool
        let coldPipelines: Bool
        let gpuCulling: Bool
        let textureStreaming: Bool
        let textureBudgetMB: Int?
        let renderScale: RenderScale
        let upscaler: UpscalerKind
        let frameInterpolation: Bool
        let meshShaderGrass: Bool

        init(scanner: inout ArgumentScanner) throws {
            outPath = try scanner.option("--out")
            framePath = try scanner.option("--frame")
            let standard = PerformanceBenchmarkPlan.standard
            let size = try scanner.option("--size").map { try RenderCommand.parseSize($0) }
                ?? (width: standard.frameWidth, height: standard.frameHeight)
            plan = standard.resized(width: size.width, height: size.height)
            let seconds = try scanner.option("--launch-seconds").map(Self.seconds)
            if scanner.flag("--launch") || seconds != nil {
                launch = try BenchmarkLaunchRequest(
                    processStart: Self.processStart(), seconds: seconds ?? 60
                )
            } else {
                launch = nil
            }
            route = scanner.flag("--route")
            coldPipelines = scanner.flag("--cold-pipelines")
            gpuCulling = !scanner.flag("--cpu-culling")
            textureBudgetMB = try scanner.option("--texture-budget").map(Self.mebibytes)
            textureStreaming = scanner.flag("--texture-streaming") || textureBudgetMB != nil
            renderScale = try scanner.option("--render-scale").map(Self.renderScale) ?? .off
            upscaler = try scanner.option("--upscaler").map(Self.upscaler) ?? .temporal
            frameInterpolation = scanner.flag("--frame-interpolation")
            meshShaderGrass = scanner.flag("--mesh-shader-grass")
        }

        func apply(to renderer: Renderer) {
            renderer.gpuCullingEnabled = gpuCulling
            renderer.textureStreaming.enabled = textureStreaming
            if let textureBudgetMB {
                renderer.textureStreaming.budgetBytes = textureBudgetMB << 20
            }
            renderer.renderScale = renderScale
            renderer.upscaler = upscaler
            renderer.frameInterpolationEnabled = frameInterpolation
            renderer.meshShaderGrassEnabled = meshShaderGrass
        }

        /// The view loads on the main actor, so the library reads levels again inline.
        func attachStreaming(textures: TextureLibrary, to renderer: Renderer) {
            guard textureStreaming else { return }
            textures.streaming = renderer.textureStreaming.mailbox
            renderer.textureStreaming.reader = InlineTextureLevelReader(library: textures)
        }

        private static func mebibytes(_ value: String) throws -> Int {
            guard let mebibytes = Int(value), mebibytes > 0 else {
                throw CLIError.usage("--texture-budget expects a MiB count, got \(value)")
            }
            return mebibytes
        }

        private static func upscaler(_ value: String) throws -> UpscalerKind {
            switch value {
            case "temporal": .temporal
            case "spatial": .spatial
            default: throw CLIError.usage("--upscaler expects temporal or spatial, got \(value)")
            }
        }

        private static func renderScale(_ value: String) throws -> RenderScale {
            guard let percent = Int(value), (50 ... 100).contains(percent) else {
                throw CLIError
                    .usage("--render-scale expects a percent from 50 to 100, got \(value)")
            }
            return RenderScale(percent: percent)
        }

        private static func seconds(_ value: String) throws -> Double {
            guard let seconds = Double(value), seconds > 0 else {
                throw CLIError.usage("--launch-seconds expects a positive number, got \(value)")
            }
            return seconds
        }

        /// The kernel's record of when this process started.
        private static func processStart() throws -> Date {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else {
                throw CLIError.failure("sysctl could not read the process start time")
            }
            let started = info.kp_proc.p_starttime
            return Date(
                timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1e6
            )
        }
    }

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let options = try Options(scanner: &scanner)
        let assets = try AssetLoadOptions(scanner: &scanner, context: context)
        try scanner.finish()
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }
        let plan = options.plan
        let setupStart = DispatchTime.now().uptimeNanoseconds
        let renderer = try makeRenderer(
            device: device, plan: plan, coldPipelines: options.coldPipelines
        )
        let setupMS = Double(DispatchTime.now().uptimeNanoseconds - setupStart) / 1e6
        options.apply(to: renderer)
        var fastLoader: FastTextureLoader?
        var result = try PerformanceBenchmark.run(
            plan: plan,
            machine: .current(gpu: device.name),
            renderer: renderer,
            launch: options.launch
        ) { recorder in
            let builder = try RenderCommand.makeBuilder(
                context: context, device: device, recorder: recorder, assets: assets
            )
            fastLoader = builder.textures.fastLoader
            options.attachStreaming(textures: builder.textures, to: renderer)
            return builder
        }
        result.pipelines = BenchmarkPipelines(
            rendererSetupMS: setupMS, stats: renderer.pipelineCache.stats
        )
        if let framePath = options.framePath {
            try writeView(renderer: renderer, plan: plan, to: framePath)
        }
        if options.textureStreaming {
            result.textureStreaming = BenchmarkTextureStreaming(
                stats: renderer.textureStreaming.stats
            )
        }
        if options.route {
            result.route = try runRoute(
                renderer: renderer, plan: plan,
                builder: RenderCommand.makeBuilder(context: context, device: device, assets: assets)
            )
        }
        report(result)
        try assets.report(fastLoader: fastLoader)
        if let outPath = options.outPath {
            let url = URL(fileURLWithPath: outPath)
            try result.jsonData().write(to: url)
            print("[INFO] wrote result -> \(url.path(percentEncoded: false))")
        }
        guard result.isComparable else {
            throw CLIError.failure("a cell failed to build; this result does not compare")
        }
    }

    /// The walk route. Its cell build worker reads streamed texture levels again.
    private static func runRoute(
        renderer: Renderer, plan: PerformanceBenchmarkPlan, builder: CellSceneBuilder
    ) throws -> BenchmarkRoute {
        try PerformanceBenchmarkRoute.run(
            renderer: renderer,
            provider: BuilderCellSceneProvider(
                builder: builder,
                worldspaceEditorID: plan.worldspace
            ),
            worldspace: plan.worldspace,
            plan: plan
        )
    }

    /// A paused offscreen renderer; the view only carries the pixel formats. Its
    /// pipelines use the cache the settings ask for; `coldPipelines` clears it first.
    private static func makeRenderer(
        device: MTLDevice,
        plan: PerformanceBenchmarkPlan,
        coldPipelines: Bool
    ) throws -> Renderer {
        let store = PlayerSettingsStore(persistence: try? PlayerSettingsFile.defaultFile())
        if coldPipelines, let folder = PipelineCache.archiveFolder(store: store) {
            try PipelineCacheFolder.clear(folder: folder)
        }
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

    private static func writeView(
        renderer: Renderer,
        plan: PerformanceBenchmarkPlan,
        to path: String
    ) throws {
        let texture = try renderer.renderOffscreen(width: plan.frameWidth, height: plan.frameHeight)
        let url = URL(fileURLWithPath: path)
        try FrameScreenshot.write(texture: texture, to: url)
        print("[INFO] wrote benchmark view -> \(url.path(percentEncoded: false))")
    }
}
