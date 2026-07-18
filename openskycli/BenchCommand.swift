// `bench`: sustained offscreen render of one exterior cell — the milestone 2
// fps gate (todo 2.11, ">30 fps sustained on M1, measured via 2.6 frame
// stats, not eyeballed"). Every frame runs through FrameStats + counter-heap
// GPU timestamps (Renderer.renderOffscreenSustained); frames are synchronous,
// so per-frame wall time is a conservative upper bound on the pipelined
// draw loop. Exit 1 when avg or p95 misses the frame-time budget.

import Foundation
import Metal
import MetalKit

enum BenchCommand {
    /// 30 fps -> 33.33 ms per frame.
    private static let defaultBudgetMS = 1000.0 / 30.0
    private static let defaultFrames = 360 // 3 full FrameStats windows

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let worldspace = try scanner.option("--worldspace")
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = try RenderCommand.int32(scanner.option("--x"), name: "--x")
            ?? FirstRenderCell.gridX
        let gridY = try RenderCommand.int32(scanner.option("--y"), name: "--y")
            ?? FirstRenderCell.gridY
        let size = try RenderCommand.parseSize(scanner.option("--size"))
        let frames = try frameCount(scanner.option("--frames"))
        let budget = try budgetMS(scanner.option("--budget-ms"))
        try scanner.finish()

        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }

        let cellScene = try RenderCommand.buildScene(
            context: context,
            device: device,
            worldspace: worldspace,
            gridX: gridX,
            gridY: gridY
        )
        print(cellScene.summary.summaryLine)
        guard let bounds = cellScene.bounds else {
            throw CLIError.failure("nothing drew — no bounds to frame a camera on")
        }

        // Headless MTKView carries pixel-format config only (render command
        // pattern); the offscreen path never touches its drawable.
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: size.width, height: size.height),
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
            width: size.width,
            height: size.height,
            frames: frames
        )
        report(result: result, size: size, frames: frames, budget: budget)
        let avg = result.averageMS
        let p95 = result.percentileMS(95)
        guard avg <= budget, p95 <= budget else {
            throw CLIError.failure(String(
                format: "frame time over budget: avg %.2f ms / p95 %.2f ms vs %.2f ms",
                avg, p95, budget
            ))
        }
        print(String(format: "[ OK ] sustained frame time within %.2f ms budget", budget))
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
}
