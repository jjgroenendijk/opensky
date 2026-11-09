// A session scope built over a real stage builds every adapter and coordinator, and
// starts. An adapter that read a coordinator in its initializer would build itself again
// and never return. Needs Metal 4.

import MetalKit
@testable import OpenSky
@testable import OpenSkyCells
import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyTagsTesting
import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldTesting
import Testing

@MainActor
@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct GameSessionScopeStageTests {
    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func aScopeOverAStageBuildsAndStarts() throws {
        let device = try #require(OffscreenRendererFixture.device)
        let view = OffscreenRendererFixture.pausedView(device: device, width: 64, height: 64)
        let gameSession = try GameSession(view: view)
        let scope = GameSessionScope(
            worldData: WorldDataStores(
                scriptFormIDResolver: FormIDResolver(pluginName: "Skyrim.esm", masters: [])
            ),
            cellRunner: nil,
            gameSession: gameSession,
            streamer: CellStreamerFixture.makeStreamer(runner: ManualCellBuildRunner()),
            services: GameAppServices()
        )
        #expect(scope.stage != nil)
        scope.start()
        #expect(gameSession.animationEvents != nil)
        _ = scope.scripts
        _ = scope.inventory
        _ = scope.magic
        _ = scope.effects
        _ = scope.combat
        _ = scope.furniture
    }
}
