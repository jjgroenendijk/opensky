// A spectator keeps watching for a few seconds after the fight near it ends.

import OpenSkyAIPackages
import OpenSkyFormatsESM
import OpenSkyWorldInterface
import Testing

struct SpectatorMemoryTests {
    private let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x10)

    @Test func aSpectatorKeepsWatchingUntilTheTimerRunsOut() {
        var memory = SpectatorMemory(rememberSeconds: 5)
        let watching = memory.remembering([actor: .spectator], actors: [actor], delta: 1)
        #expect(watching[actor] == .spectator)
        #expect(memory.remembering([:], actors: [actor], delta: 4)[actor] == .spectator)
        #expect(memory.remembering([:], actors: [actor], delta: 2)[actor] == nil)
    }

    @Test func anotherSituationEndsTheMemory() {
        var memory = SpectatorMemory(rememberSeconds: 5)
        _ = memory.remembering([actor: .spectator], actors: [actor], delta: 1)
        #expect(memory.remembering([actor: .combat], actors: [actor], delta: 1)[actor] == .combat)
        #expect(memory.remembering([:], actors: [actor], delta: 1)[actor] == nil)
    }
}
