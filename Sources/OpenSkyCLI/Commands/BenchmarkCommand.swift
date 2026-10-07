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
        let renderer = try makeRenderer(device: device, plan: plan)
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
            return builder
        }
        if let framePath = options.framePath {
            try writeView(renderer: renderer, plan: plan, to: framePath)
        }
        if options.route {
            let builder = try RenderCommand.makeBuilder(
                context: context, device: device, assets: assets
            )
            result.route = try PerformanceBenchmarkRoute.run(
                renderer: renderer,
                provider: BuilderCellSceneProvider(
                    builder: builder,
                    worldspaceEditorID: plan.worldspace
                ),
                worldspace: plan.worldspace,
                plan: plan
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

    /// A paused offscreen renderer; the view only carries the pixel formats.
    private static func makeRenderer(
        device: MTLDevice,
        plan: PerformanceBenchmarkPlan
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
            movementConfiguration: .synthetic
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
