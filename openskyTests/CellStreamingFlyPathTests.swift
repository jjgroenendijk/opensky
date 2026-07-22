// Pure scripted fly-path tests: pin waypoint order, interpolation endpoints,
// and 5x5 union size without Metal or game data. Runtime settlement, memory,
// unload, and build-count gates live in `openskycli bench --fly-path`.

@testable import opensky
import Testing

struct CellStreamingFlyPathTests {
    @Test
    func waypointsCrossEastThenNorth() {
        let start = CellCoordinate(x: 6, y: -2)
        #expect(CellStreamingFlyPath.waypoints(start: start) == [
            start,
            CellCoordinate(x: 7, y: -2),
            CellCoordinate(x: 7, y: -1)
        ])
    }

    @Test
    func positionsEndAtNextCellCenter() {
        let start = CellCoordinate(x: 6, y: -2)
        let end = CellCoordinate(x: 7, y: -2)
        let positions = CellStreamingFlyPath.positions(from: start, to: end, samples: 4)
        #expect(positions.count == 4)
        #expect(positions.last == CellGridManager.cellCenter(of: end))
        #expect(positions[0].x > CellGridManager.cellCenter(of: start).x)
    }

    @Test
    func adjacentFiveByFiveGridsNeedThirtyFiveUniqueBuilds() {
        let cells = CellStreamingFlyPath.expectedCells(
            start: CellCoordinate(x: 6, y: -2),
            radius: CellGridManager.defaultRadius
        )
        #expect(cells.count == 35)
    }

    /// A shadow-update run over budget must produce the reason-tagged error
    /// exactly like the animation gate; the description carries the numbers the
    /// acceptance record needs. (Same avg/p95 accessors the Driver guard uses.)
    @Test
    func shadowUpdateBudgetViolationSurfacesAveragesAndBudget() {
        let render = OffscreenBenchResult(
            frameMS: [8, 8, 8],
            windowSummaries: [],
            shadowMS: [4, 5, 6] // avg 5, p95 6 — over a tiny budget
        )
        let budget = 1.5
        #expect(render.shadowAverageMS > budget)
        #expect(render.shadowPercentileMS(95) > budget)
        let error = CellStreamingFlyBenchmarkError.shadowUpdateExceeded(
            average: render.shadowAverageMS,
            p95: render.shadowPercentileMS(95),
            budget: budget
        )
        #expect(
            error.errorDescription
                == "shadow update avg 5.00 ms / p95 6.00 ms exceeded 1.50 ms budget"
        )
    }

    /// The report struct threads final-frame ShadowDrawStats + the budget so the
    /// CLI can print per-cascade culling evidence without a live renderer here.
    @Test
    func resultCarriesShadowStatsAndBudget() {
        let stats = ShadowDrawStats(
            drawCalls: 12,
            drawnInstances: 40,
            culledInstances: 7,
            cascadesRendered: 3
        )
        let result = CellStreamingFlyPathTests.makeResult(
            shadowBudgetMS: 1.5,
            shadowStats: stats
        )
        #expect(result.shadowUpdateBudgetMS == 1.5)
        #expect(result.shadowDrawStats == stats)
        #expect(result.shadowDrawStats.culledInstances == 7)
        #expect(result.shadowDrawStats.cascadesRendered == 3)
    }

    private static func makeResult(
        shadowBudgetMS: Double,
        shadowStats: ShadowDrawStats
    ) -> CellStreamingFlyBenchmarkResult {
        CellStreamingFlyBenchmarkResult(
            render: OffscreenBenchResult(frameMS: [8], windowSummaries: []),
            settledFootprintsMB: [100],
            peakFootprintMB: 100,
            uniqueBuildCount: 35,
            unloadedCellCount: 5,
            finalResidentCellCount: 25,
            finalVoidCellCount: 0,
            footprintCapMB: 1024,
            collisionBuildAverageMS: 0,
            collisionBuildP95MS: 0,
            collisionBuildMaximumMS: 0,
            collisionBuildBudgetMS: 700,
            collisionShapeCount: 0,
            collisionTriangleCount: 0,
            actorBuildAverageMS: 0,
            actorBuildP95MS: 0,
            actorBuildMaximumMS: 0,
            actorBuildBudgetMS: 4500,
            actorDiscoveredCount: 0,
            actorRenderedCount: 0,
            actorDisabledSkipCount: 0,
            actorFailureCount: 0,
            actorAnimatedCount: 0,
            actorAnimationFailureCount: 0,
            animationUpdateBudgetMS: 4,
            shadowUpdateBudgetMS: shadowBudgetMS,
            weatherName: "Rain",
            windSpeed: 0.5,
            animationUpdatedBoneCount: 10,
            particleSystemCount: 2,
            particleLiveCount: 20,
            rainLiveCount: 128,
            shadowDrawStats: shadowStats,
            grassDrawStats: GrassDrawStats(drawCalls: 2, drawnInstances: 20),
            actorCellReports: []
        )
    }
}
