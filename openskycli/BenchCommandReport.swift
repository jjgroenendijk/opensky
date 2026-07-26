// Text reporting for `bench`, split from BenchCommand.swift (file-length
// limit). Every function here only formats and prints: the gates that decide
// pass or fail live in BenchCommand.swift and in the shared engine drivers.

import Foundation

extension BenchCommand {
    static func reportWalkPath(
        result: CellStreamingWalkBenchmarkResult,
        size: (width: Int, height: Int),
        budget: Double,
        audioBudget: Double
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
        reportAudioUpdate(render: render, budget: audioBudget)
    }

    static func reportFlyPath(
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
        reportFlyMetrics(result)
        reportFlyActors(result)
        print(String(
            format: "[INFO] %d stream frames @ %dx%d: avg %.2f ms, p95 %.2f ms, "
                + "max %.2f ms, budget %.2f ms",
            result.render.frameMS.count, size.width, size.height,
            result.render.averageMS, result.render.percentileMS(95),
            result.render.frameMS.max() ?? 0, budget
        ))
    }

    static func reportFlyMetrics(_ result: CellStreamingFlyBenchmarkResult) {
        print(
            "[INFO] living environment: weather \(result.weatherName), wind "
                + String(format: "%.3f", result.windSpeed)
                + "; \(result.animationUpdatedBoneCount) animated bones; "
                + "\(result.particleLiveCount) live particles in "
                + "\(result.particleSystemCount) systems; "
                + "\(result.rainLiveCount) live rain"
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
        reportFlyUpdateBudgets(result)
        let shadow = result.shadowDrawStats
        print(
            "[INFO] shadow culling: \(shadow.drawCalls) draw calls, "
                + "\(shadow.drawnInstances) drawn, "
                + "\(shadow.culledInstances) culled, "
                + "\(shadow.cascadesRendered) cascades"
        )
        let grass = result.grassDrawStats
        print(
            "[INFO] grass instancing: \(grass.drawCalls) draw calls, "
                + "\(grass.drawnInstances)/\(grass.sceneInstances) drawn, "
                + "\(grass.densityCulledInstances) density-culled, "
                + "\(grass.distanceCulledInstances) distance-culled, "
                + "\(grass.frustumCulledInstances) frustum-culled, "
                + "\(grass.budgetDroppedInstances) budget-dropped"
        )
    }

    /// The three per-frame CPU update gates, in the order the fly benchmark
    /// validates them.
    static func reportFlyUpdateBudgets(_ result: CellStreamingFlyBenchmarkResult) {
        print(String(
            format: "[INFO] animation update: avg %.2f ms, p95 %.2f ms, "
                + "max %.2f ms, budget %.2f ms",
            result.render.animationAverageMS,
            result.render.animationPercentileMS(95),
            result.render.animationMS.max() ?? 0,
            result.animationUpdateBudgetMS
        ))
        print(String(
            format: "[INFO] shadow update: avg %.2f ms, p95 %.2f ms, "
                + "max %.2f ms, budget %.2f ms",
            result.render.shadowAverageMS,
            result.render.shadowPercentileMS(95),
            result.render.shadowMS.max() ?? 0,
            result.shadowUpdateBudgetMS
        ))
        reportAudioUpdate(render: result.render, budget: result.audioUpdateBudgetMS)
    }

    static func reportFlyActors(_ result: CellStreamingFlyBenchmarkResult) {
        // Per-cell accounting before the totals: 5.6 acceptance requires the
        // probe to report counts for each touched cell, failures with reasons.
        for report in result.actorCellReports {
            var line = "[INFO] cell (\(report.coordinate.x),\(report.coordinate.y)) actors: "
                + "\(report.discovered) discovered = \(report.rendered) rendered + "
                + "\(report.disabledSkips) disabled + \(report.failures) failed"
            if !report.failureReasons.isEmpty {
                line += " [\(report.failureReasons.joined(separator: "; "))]"
            }
            line += "; \(report.animated) animated + "
                + "\(report.animationFailures) static"
            if !report.animationFailureReasons.isEmpty {
                line += " [\(report.animationFailureReasons.joined(separator: "; "))]"
            }
            print(line)
        }
        print(
            "[INFO] actors: \(result.actorDiscoveredCount) discovered = "
                + "\(result.actorRenderedCount) rendered + "
                + "\(result.actorDisabledSkipCount) disabled + "
                + "\(result.actorFailureCount) failed"
        )
        print(
            "[INFO] rendered actors: \(result.actorAnimatedCount) animated + "
                + "\(result.actorAnimationFailureCount) static"
        )
    }

    static func report(
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

    static func reportAudioUpdate(
        render: OffscreenBenchResult,
        budget: Double
    ) {
        print(String(
            format: "[INFO] audio update: avg %.3f ms, p95 %.3f ms, "
                + "max %.3f ms, budget %.2f ms",
            render.audioUpdateAverageMS,
            render.audioUpdatePercentileMS(95),
            render.audioUpdateMS.max() ?? 0,
            budget
        ))
    }
}
