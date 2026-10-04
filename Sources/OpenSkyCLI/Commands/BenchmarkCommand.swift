// `benchmark`: the shared performance benchmark on the real install. Prints a
// summary and writes the stable JSON result (docs/tools/benchmark.md).

import Foundation
import Metal
import MetalKit
import OpenSkyRendering
import OpenSkyWorld

enum BenchmarkCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let outPath = try scanner.option("--out")
        let framePath = try scanner.option("--frame")
        try scanner.finish()
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }
        let plan = PerformanceBenchmarkPlan.standard
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: plan.frameWidth, height: plan.frameHeight),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: RenderScene(instances: []),
            movementConfiguration: .synthetic
        )
        let result = try PerformanceBenchmark.run(
            plan: plan,
            machine: .current(gpu: device.name),
            renderer: renderer
        ) { recorder in
            try RenderCommand.makeBuilder(context: context, device: device, recorder: recorder)
        }
        report(result)
        if let outPath {
            let url = URL(fileURLWithPath: outPath)
            try result.jsonData().write(to: url)
            print("[INFO] wrote result -> \(url.path(percentEncoded: false))")
        }
        if let framePath {
            let texture = try renderer.renderOffscreen(
                width: plan.frameWidth, height: plan.frameHeight
            )
            let url = URL(fileURLWithPath: framePath)
            try FrameScreenshot.write(texture: texture, to: url)
            print("[INFO] wrote benchmark view -> \(url.path(percentEncoded: false))")
        }
        guard result.isComparable else {
            throw CLIError.failure("a cell failed to build; this result does not compare")
        }
    }

    private static func report(_ result: PerformanceBenchmarkResult) {
        let machine = result.machine
        print(
            "[INFO] machine: \(machine.modelIdentifier), \(machine.cpu) "
                + "(\(machine.logicalCores) cores), \(machine.gpu), "
                + String(format: "%.0f GB, ", machine.memoryGB) + machine.osVersion
                + "; build \(result.buildConfiguration.rawValue); started "
                + result.startedAt.ISO8601Format()
        )
        for (name, pass) in [("cold", result.coldLoad), ("warm", result.warmLoad)] {
            print("[INFO] \(name) load: " + String(
                format: "%.0f ms total, %.0f ms setup", pass.totalMS, pass.setupMS
            ))
            let ranked = pass.rankedPhases
                .map { "\($0.name) " + String(format: "%.0f ms", $0.ms) }
                .joined(separator: ", ")
            print("[INFO] \(name) phases: \(ranked)")
            for cell in pass.cells {
                let status = cell.error.map { " [ERROR] \($0)" } ?? ""
                print("[INFO]   \(cell.label): " + String(format: "%.0f ms", cell.totalMS) + status)
            }
        }
        let frame = result.frameTime
        print(String(
            format: "[INFO] frame time over %d frames @ %dx%d: "
                + "avg %.2f ms, p95 %.2f ms, worst %.2f ms; %d draw calls, %d instances",
            frame.frames, result.plan.frameWidth, result.plan.frameHeight,
            frame.averageMS, frame.percentile95MS, frame.worstMS,
            frame.drawCalls, frame.drawnInstances
        ))
    }
}
