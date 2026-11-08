// Walks the fixed route: terrain, the farm stairs, through a door into an interior,
// and back out. Checks the physics frame budget and the audio budget.

import OpenSkyCells
import OpenSkyRendering
import OpenSkyTagsTesting
import OpenSkyWorld
import Testing

@Suite(.tags(.perf, .gpu, .slow))
struct WalkPathGateRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.canTimeFrames))
    @MainActor
    func walkPathStaysWithinBudgets() throws {
        let builder = try StreamingGateSupport.makeBuilder()
        let provider = BuilderCellSceneProvider(
            builder: builder, worldspaceEditorID: FirstRenderCell.worldspaceEditorID
        )
        let session = try StreamingGateSupport.makeStreamSession()
        let result = try CellStreamingWalkBenchmark.run(
            gameSession: session, provider: provider,
            configuration: CellStreamingWalkBenchmarkConfiguration(
                size: StreamingGateBudget.size, maxFrames: 36000
            )
        )
        let budget = WalkBenchmarkFrameBudget.buildDefault(
            frameIntervalMS: StreamingGateBudget.frameMS,
            debugBuild: StreamingGateBudget.isDebugBuild
        )
        let physics = result.physicsRender
        #expect(
            budget.contains(physics),
            "physics avg \(physics.averageMS) ms, p95 \(physics.percentileMS(95)) ms"
        )
        #expect(physics.audioUpdateAverageMS <= StreamingGateBudget.audioUpdateMS)
        #expect(physics.audioUpdatePercentileMS(95) <= StreamingGateBudget.audioUpdateMS)
    }
}
