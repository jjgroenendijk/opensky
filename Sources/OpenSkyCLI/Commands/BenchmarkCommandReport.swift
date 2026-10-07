// The printed summary of the shared benchmark. The JSON result holds the same
// numbers (docs/tools/benchmark.md).

import Foundation
import OpenSkyWorld

extension BenchmarkCommand {
    static func report(_ result: PerformanceBenchmarkResult) {
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
            reportCells(pass.cells)
        }
        reportFrameTime(result)
        if let launch = result.launch {
            print(String(
                format: "[INFO] launch: %.0f ms from process start to the first frame, "
                    + "first frame %.1f ms; ",
                launch.processToFirstFrameMS, launch.firstFrameMS
            ) + describe(launch.frameTime, over: String(format: "%.0f s", launch.seconds)))
        }
        if let route = result.route {
            print("[INFO] route: " + describe(route.frameTime, over: "the walk route"))
            if let gpu = route.gpuTime {
                print("[INFO] route GPU: " + describe(gpu, over: "the walk route"))
            }
            if let loads = route.cellLoadTime {
                print(String(
                    format: "[INFO] route loads: %d builds, "
                        + "avg %.0f ms, p95 %.0f ms, worst %.0f ms",
                    loads.frames, loads.averageMS, loads.percentile95MS, loads.worstMS
                ))
            }
            reportCells(route.cellLoads)
        }
    }

    private static func reportFrameTime(_ result: PerformanceBenchmarkResult) {
        let frame = result.frameTime
        print(String(
            format: "[INFO] frame time over %d frames @ %dx%d: "
                + "avg %.2f ms, p95 %.2f ms, worst %.2f ms; %d draw calls, %d instances",
            frame.frames, result.plan.frameWidth, result.plan.frameHeight,
            frame.averageMS, frame.percentile95MS, frame.worstMS,
            frame.drawCalls, frame.drawnInstances
        ))
        if let gpu = frame.gpuTime {
            print("[INFO] GPU time: " + describe(gpu, over: "the measured frames"))
        }
        if let grass = frame.grass {
            print(
                "[INFO] grass: \(grass.drawCalls) draw calls, "
                    + "\(grass.drawnInstances)/\(grass.sceneInstances) instances drawn"
            )
        }
        if let memory = result.gpuMemory {
            for (name, sample) in [("peak", memory.peak), ("last", memory.last)] {
                print(String(
                    format: "[INFO] GPU memory %@: %.0f MiB allocated, "
                        + "%.0f MiB render targets, %.0f MiB textures",
                    name, sample.totalMB, sample.renderTargetMB, sample.textureMB
                ))
            }
        }
    }

    private static func reportCells(_ cells: [BenchmarkCellLoad]) {
        for cell in cells {
            let status = cell.error.map { " [ERROR] \($0)" } ?? ""
            print("[INFO]   \(cell.label): " + String(format: "%.0f ms", cell.totalMS) + status)
        }
    }

    private static func describe(_ stats: BenchmarkTimeStats, over span: String) -> String {
        String(
            format: "%d frames over %@: avg %.2f ms, p95 %.2f ms, worst %.2f ms",
            stats.frames, span, stats.averageMS, stats.percentile95MS, stats.worstMS
        )
    }
}
