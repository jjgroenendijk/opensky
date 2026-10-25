// Flies east and north across Tamriel cells through the real streamer and checks
// memory, single builds, actor builds, living systems, and the frame budget.

import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyRendering
import OpenSkyTagsTesting
import OpenSkyTerrain
import OpenSkyWeather
import OpenSkyWorld
import Testing

@Suite(.tags(.perf, .gpu, .slow))
struct FlyPathGateRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func flyPathStaysWithinBudgets() throws {
        let worldspace = FirstRenderCell.worldspaceEditorID
        let builder = try StreamingGateSupport.makeBuilder()
        let weather = WeatherSystem(
            loadOrder: builder.pluginLoadOrder,
            worldspaceEditorID: worldspace
        )
        let lodPrebuild = builder.distantLODBuilder?.prebuild(worldspace: worldspace)
        let provider = BuilderCellSceneProvider(builder: builder, worldspaceEditorID: worldspace)
        let session = try StreamingGateSupport.makeStreamSession()
        StreamingGateSupport.attachEmptyScriptRuntime(to: session)
        let result = try CellStreamingFlyBenchmark.run(
            gameSession: session, provider: provider, lodPrebuild: lodPrebuild, weather: weather,
            configuration: CellStreamingFlyBenchmarkConfiguration(
                start: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
                size: StreamingGateBudget.size,
                maxFrames: 36000,
                footprintCapMB: StreamingGateBudget.footprintCapMB,
                collisionBuildBudgetMS: StreamingGateBudget.collisionBuildMS,
                actorBuildBudgetMS: StreamingGateBudget.actorBuildMS,
                animationUpdateBudgetMS: StreamingGateBudget.animationUpdateMS,
                shadowUpdateBudgetMS: StreamingGateBudget.shadowUpdateMS,
                audioUpdateBudgetMS: StreamingGateBudget.audioUpdateMS,
                scriptUpdateBudgetMS: StreamingGateBudget.scriptUpdateMS
            )
        )
        // The engine gate already threw on a missed build or memory budget; these
        // check that each living system ran during the flight.
        #expect(result.actorCellCount == 35, "three settled 5 by 5 grids")
        #expect(result.actorAnimatedCount > 0)
        #expect(!result.weatherName.isEmpty)
        #expect(result.animationUpdatedBoneCount > 0)
        #expect(result.particleLiveCount > 0 && result.particleSystemCount > 0)
        #expect(result.rainLiveCount > 0)
        #expect(result.shadowDrawStats.culledInstances > 0)
        #expect(result.grassDrawStats.drawnInstances > 0)
        #expect(result.grassDrawStats.budgetDroppedInstances == 0)
        #expect(
            result.render.averageMS <= StreamingGateBudget.frameMS,
            "avg \(result.render.averageMS) ms"
        )
        #expect(
            result.render.percentileMS(95) <= StreamingGateBudget.frameMS,
            "p95 \(result.render.percentileMS(95)) ms"
        )
    }
}
