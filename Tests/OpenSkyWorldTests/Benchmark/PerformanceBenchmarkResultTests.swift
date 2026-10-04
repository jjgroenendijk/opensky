// The benchmark's fixed plan and its stable JSON shape, over synthetic numbers.
// No Metal device or game data is required.

import Foundation
import OpenSkyGameData
import OpenSkyWorld
import Testing

struct PerformanceBenchmarkResultTests {
    private static func result(cellError: String? = nil) -> PerformanceBenchmarkResult {
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
                drawCalls: 900, drawnInstances: 4000
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
    }
}
