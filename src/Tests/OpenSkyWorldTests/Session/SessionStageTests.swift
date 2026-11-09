// The session stage holds the parts every adapter is built over.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldTesting
import Testing

@MainActor
struct SessionStageTests {
    private final class StandInSession {}

    @Test func aStageKeepsTheSessionStreamerAndDataItWasBuiltOver() {
        let session = StandInSession()
        let streamer = CellStreamerFixture.makeStreamer(runner: ManualCellBuildRunner())
        let resolver = FormIDResolver(pluginName: "Skyrim.esm", masters: [])
        let data = WorldDataStores(scriptFormIDResolver: resolver)
        let stage = SessionStageParts(gameSession: session, streamer: streamer, data: data)
        #expect(stage.gameSession === session)
        #expect(stage.streamer === streamer)
        #expect(stage.data.scriptFormIDResolver == resolver)
    }
}
