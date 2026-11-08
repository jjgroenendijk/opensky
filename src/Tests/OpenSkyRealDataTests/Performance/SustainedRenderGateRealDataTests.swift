// Renders the first cell offscreen for 360 frames and checks the frame budget.

import OpenSkyCells
import OpenSkyRendering
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.perf, .gpu, .slow))
struct SustainedRenderGateRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func sustainedRenderStaysWithinFrameBudget() throws {
        let scene = try StreamingGateSupport.makeBuilder().buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: FirstRenderCell.gridX, gridY: FirstRenderCell.gridY
        )
        let bounds = try #require(scene.bounds, "nothing drew")
        let renderer = try Renderer(
            rendering: StreamingGateSupport.makeView(), scene: scene.renderScene,
            camera: SceneCamera.framing(bounds: bounds)
        )
        let size = StreamingGateBudget.size
        let result = try renderer.renderOffscreenSustained(
            width: size.width,
            height: size.height,
            frames: 360
        )
        #expect(result.averageMS <= StreamingGateBudget.frameMS, "avg \(result.averageMS) ms")
        #expect(
            result.percentileMS(95) <= StreamingGateBudget.frameMS,
            "p95 \(result.percentileMS(95)) ms"
        )
    }
}
