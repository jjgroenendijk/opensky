// The benchmark's fixed plan and its stable JSON shape, over synthetic numbers.
// No Metal device or game data is required.

import Foundation
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld
import Testing

struct PerformanceBenchmarkResultTests {
    private static let timeStats = BenchmarkTimeStats(
        frames: 600, averageMS: 4.5, percentile95MS: 6.25, worstMS: 9
    )

    private static func result(
        cellError: String? = nil,
        routeError: String? = nil
    ) -> PerformanceBenchmarkResult {
        var result = baseResult(cellError: cellError)
        let sample = BenchmarkGPUMemorySample(totalMB: 900, renderTargetMB: 60, textureMB: 500)
        result.gpuMemory = BenchmarkGPUMemory(peak: sample, last: sample)
        result.launch = BenchmarkLaunch(
            processToFirstFrameMS: 4200, firstFrameMS: 310, seconds: 60, frameTime: timeStats
        )
        result.route = BenchmarkRoute(
            frameTime: timeStats,
            gpuTime: timeStats,
            cellLoads: [BenchmarkCellLoad(label: "Tamriel (8,-3)", totalMS: 180, error: routeError)]
        )
        return result
    }

    private static func baseResult(cellError: String?) -> PerformanceBenchmarkResult {
        let phases = LoadPhaseTimes(archiveMS: 40, textureMS: 120, meshMS: 80, collisionMS: 10)
        return PerformanceBenchmarkResult(
            startedAt: Date(timeIntervalSince1970: 1_790_000_000),
            machine: BenchmarkMachine(
                modelIdentifier: "Mac15,9", cpu: "Apple M3 Max", gpu: "Apple M3 Max",
                logicalCores: 16, memoryGB: 64, osVersion: "Version 26.0"
            ),
            buildConfiguration: .release,
            plan: .standard,
            coldLoad: BenchmarkLoadPass(
                totalMS: 300,
                setupMS: 25,
                phases: phases.completed(totalMS: 300),
                cells: [BenchmarkCellLoad(label: "Tamriel (6,-2)", totalMS: 275, error: cellError)]
            ),
            warmLoad: BenchmarkLoadPass(
                totalMS: 50, setupMS: 0, phases: LoadPhaseTimes(otherMS: 50), cells: []
            ),
            frameTime: BenchmarkFrameTime(
                frames: 600, averageMS: 8.5, percentile95MS: 10.25, worstMS: 21,
                drawCalls: 900, drawnInstances: 4000,
                gpuTime: timeStats,
                grass: BenchmarkGrass(sceneInstances: 3000, drawCalls: 12, drawnInstances: 2100)
            )
        )
    }

    @Test
    func standardPlanIsTheFirstRenderBlockAndTheFarmInteriorSeenFromTheWalkStart() {
        let plan = PerformanceBenchmarkPlan.standard
        #expect(plan.worldspace == "Tamriel")
        #expect(plan.exteriorCells.count == 9)
        #expect(plan.exteriorCells[4] == BenchmarkGridCell(x: 6, y: -2))
        #expect(plan.exteriorCells.first == BenchmarkGridCell(x: 5, y: -3))
        #expect(plan.interiorCellFormIDs == [0x0001_6204])
        #expect(plan.centerCell == BenchmarkGridCell(x: 6, y: -2))
        #expect(plan.view.fromX == 28600)
        #expect(plan.view.fromY == -7600)
        #expect(plan.frameWidth == 2560)
        #expect(plan.frameHeight == 1600)
    }

    @Test
    func resizedKeepsTheCellsAndTheView() {
        let plan = PerformanceBenchmarkPlan.standard.resized(width: 1280, height: 720)
        #expect(plan.frameWidth == 1280)
        #expect(plan.frameHeight == 720)
        #expect(plan.exteriorCells == PerformanceBenchmarkPlan.standard.exteriorCells)
        #expect(plan.view == PerformanceBenchmarkPlan.standard.view)
    }

    @Test
    func aResultWithoutTheOptionalSectionsStillDecodes() throws {
        let original = Self.baseResult(cellError: nil)
        var text = try #require(String(bytes: original.jsonData(), encoding: .utf8))
        #expect(!text.contains("gpuMemory"))
        text = text.replacingOccurrences(of: "\"gpuTime\"", with: "\"unknownField\"")
        let decoded = try PerformanceBenchmarkResult.decode(json: Data(text.utf8))
        #expect(decoded.frameTime.gpuTime == nil)
        #expect(decoded.launch == nil)
        #expect(decoded.route == nil)
    }

    @Test
    func timeStatsUseNearestRankAndSkipEmptyRuns() throws {
        #expect(BenchmarkTimeStats(milliseconds: []) == nil)
        let stats = try #require(BenchmarkTimeStats(milliseconds: (1 ... 20).map(Double.init)))
        #expect(stats.frames == 20)
        #expect(stats.averageMS == 10.5)
        #expect(stats.percentile95MS == 19)
        #expect(stats.worstMS == 20)
    }

    @Test
    func memoryPeakTakesTheLargestValueOfEachField() {
        let first = GPUMemoryUsage(totalBytes: 10, renderTargetBytes: 5, textureBytes: 1)
        let second = GPUMemoryUsage(totalBytes: 8, renderTargetBytes: 7, textureBytes: 3)
        #expect(
            first.fieldMaximum(second)
                == GPUMemoryUsage(totalBytes: 10, renderTargetBytes: 7, textureBytes: 3)
        )
        let sample = BenchmarkGPUMemorySample(GPUMemoryUsage(totalBytes: 3 << 20))
        #expect(sample.totalMB == 3)
    }

    @Test
    func jsonRoundTripKeepsEveryValue() throws {
        let original = Self.result()
        let decoded = try PerformanceBenchmarkResult.decode(json: original.jsonData())
        #expect(decoded == original)
        #expect(decoded.schemaVersion == PerformanceBenchmarkResult.currentSchemaVersion)
    }

    @Test
    func jsonUsesStableKeysAndAnISODate() throws {
        let text = try #require(String(bytes: Self.result().jsonData(), encoding: .utf8))
        #expect(text.contains("\"startedAt\" : \"2026-09-21T"))
        #expect(text.contains("\"percentile95MS\" : 10.25"))
        #expect(text.contains("\"textureMS\" : 120"))
    }

    @Test
    func rankedPhasesPutTheLargestCostFirst() {
        let ranked = Self.result().coldLoad.rankedPhases.map(\.name)
        #expect(ranked == ["texture", "mesh", "other", "archive", "collision"])
    }

    @Test
    func aFailedCellMakesTheResultNotComparable() {
        #expect(Self.result().isComparable)
        #expect(!Self.result(cellError: "cellNotFound").isComparable)
        #expect(!Self.result(routeError: "malformedRecord").isComparable)
    }
}
