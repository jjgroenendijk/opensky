// The day stats rise once per clock move past midnight (docs/engine/statistics.md).

import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkySessionTesting
import OpenSkyStoryAdapters
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct MiscStatsDaysTests {
    @Test func aPassedDayCountsTheVampireDaysWhileItsGlobalIsSet() throws {
        let host = StoryHost()
        let session = FakeGameSessionPort()
        var time = RendererGameTime()
        time.clock = GameClock(hour: 23)
        time.passTime(wallDelta: 300, timescale: 20)
        session.gameTimeValue = time
        host.gameSession = session
        let records = FakeWorldRecords()
        records.miscStatSources = MiscStatSources(
            playerIsVampire: FormID(0x41), playerIsWerewolf: FormID(0x42)
        )
        host.worldRecords = records
        let globals = try GlobalStore(
            file: ESMFile(data: GlobalFixture.plugin(
                GlobalFixture.record(formID: 0x41, editorID: "V", type: .short, value: 1)
                    + GlobalFixture.record(formID: 0x42, editorID: "W", type: .short, value: 0)
            )),
            pluginName: "Test.esm"
        )
        host.fakeRuntimeState.globalResolutionResult = GlobalResolution(defaults: globals)
        let adapter = MiscStatsDaysAdapter(game: host)

        adapter.tick()
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.name) == [
            "Days Passed", "Days as a Vampire"
        ])
        #expect(host.fakeWorldState.incrementMiscStatCalls.allSatisfy { $0.amount == 1 })

        adapter.tick()
        #expect(host.fakeWorldState.incrementMiscStatCalls.count == 2)
    }
}
