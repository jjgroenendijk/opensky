// The World readouts' renderer controls with no renderer and no streamer: the
// state a machine without Metal 4 ends up in. Every read must fall back to its
// stated default without a GPU.

@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyRuntimeState
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

@MainActor
struct WorldRenderControlsTests {
    private let runtimeWorld = FakeRuntimeStateWorld()
    private let world = EmptyRenderControlWorld()
    private let controls: WorldRenderControls

    init() {
        let runtimeState = RuntimeStateCoordinator(store: WorldStateStore(), world: runtimeWorld)
        controls = WorldRenderControls(runtimeState: runtimeState, world: world)
    }

    @Test func cameraFallsBackWithoutARenderer() {
        #expect(controls.cameraPose == CameraPoseSnapshot.unavailable)
        controls.movementMode = .walk
        // No renderer holds the change, so the getter keeps the default.
        #expect(controls.movementMode == .fly)
    }

    @Test func statsZeroOutWithoutARendererOrStreamer() {
        #expect(controls.frameStatsSnapshot == FrameStatsSnapshot.empty)
        let stats = controls.sceneStatsSnapshot
        #expect(stats.drawCalls == 0)
        #expect(stats.drawnInstances == 0)
        #expect(stats.culledInstances == 0)
        #expect(stats.residentCellCount == 0)
        // A process reading, so it stays available without a renderer.
        #expect((stats.memoryFootprintMB ?? 0) > 0)
    }

    @Test func triggersSayTheStreamerIsMissing() {
        #expect(controls.triggerStatsSnapshot == .unavailable)
        #expect(controls.dynamicBodyStatsSnapshot == DynamicBodyStatsSnapshot())
    }

    @Test func environmentReadsKeepTheirDefaults() {
        #expect(controls.weatherEnabled)
        #expect(controls.selectableWeatherNames.isEmpty)
        #expect(controls.currentWeatherName == nil)
        #expect(controls.weatherTransitionFraction == 1)
        #expect(controls.particleEmissionScale == 1)
        #expect(controls.grassDrawDistance == GrassRenderPolicy.defaultDrawDistance)
        #expect(controls.renderDebugMode == .off)
        #expect(controls.renderDebugLayers == .all)
        #expect(!controls.shadowsActive)
    }

    /// The Environment hour control is the Runtime State scrub, so both persist.
    @Test func timeOfDayWritesThroughTheRuntimeState() {
        controls.timeOfDay = 18
        #expect(runtimeWorld.timeOfDayWrites == [18])
        #expect(runtimeWorld.persistedHours == [18])
    }

    @Test func refocusReachesTheWorld() {
        controls.refocusGameView()
        #expect(world.refocusCount == 1)
    }
}

private final class EmptyRenderControlWorld: RenderControlWorld {
    let renderer: Renderer? = nil
    let gameSession: GameSession? = nil
    let streamer: CellStreamer? = nil
    private(set) var refocusCount = 0

    func refocusGameView() {
        refocusCount += 1
    }
}
