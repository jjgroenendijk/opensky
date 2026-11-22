// The package world turns a walker through the streamer, and the offscreen pass
// reads the session's timescale.

import OpenSkyAIAdapters
import OpenSkyFormatsESM
import OpenSkySessionTesting
import Testing

@MainActor
struct AITurnAndClockTests {
    private let host = AIHost()
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    @Test func aWalkerTurnsThroughTheStreamer() {
        let adapter = AIWorldAdapter(game: host, stage: nil)
        host.fakeStreamer.actors.turnActorResult = 0.25
        #expect(adapter.worlds.turnPackageActor(Self.actor, toHeading: 1, within: 0.1) == 0.25)
        #expect(host.fakeStreamer.actors.turnActorCalls.map(\.heading) == [1])
    }

    @Test func theOffscreenPassReadsTheSessionClock() {
        let adapter = AIWorldAdapter(game: host, stage: nil)
        let session = FakeGameSessionPort()
        session.currentTimescale = 30
        host.gameSession = session
        #expect(adapter.worlds.offscreenTimescale == 30)
        #expect(adapter.worlds.offscreenStopwatch()() >= 0)
    }
}
