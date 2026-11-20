// The idles a save keeps: one kept for an actor that is not loaded yet is kept again
// by the next save, until the actor loads and plays it.

@testable import OpenSkyActorPresentation
import OpenSkyFormatsESM
import OpenSkyWorldInterface
import Testing

@MainActor
struct IdleSaveTests {
    @Test func anIdleWaitingForItsActorIsSavedAgain() {
        let idles = IdleCoordinator(world: nil, data: nil)
        let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BBD)
        let play = SavedIdlePlay(
            idle: ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x0001_0C2A), target: .player
        )
        #expect(idles.savedIdlePlays().isEmpty)
        idles.restoreIdlePlays([actor: play])
        idles.advance()
        #expect(idles.savedIdlePlays() == [actor: play])
        idles.restoreIdlePlays([:])
        #expect(idles.savedIdlePlays().isEmpty)
    }

    @Test func thePlayerPlaysItsSavedIdleAtOnce() {
        let idles = IdleCoordinator(world: nil, data: nil)
        let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BBD)
        let play = SavedIdlePlay(idle: ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x0001_0C2A))
        idles.restoreIdlePlays([.player: play, actor: play])
        idles.replaySavedPlays(actors: [:])
        #expect(idles.savedIdlePlays() == [actor: play])
    }
}
