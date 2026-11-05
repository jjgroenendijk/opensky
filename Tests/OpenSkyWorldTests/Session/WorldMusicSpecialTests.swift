// Special music (docs/engine/music.md#special-music): the default objects name the
// music of one moment. It plays one track, then the interrupted music comes back.

@testable import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorld
import OpenSkyWorldFixtures
import Testing

@MainActor
struct WorldMusicSpecialTests {
    private static func store() -> MusicRecordStore {
        MusicFixture.makeStore(
            types: [
                MusicFixture.TypeSpec(
                    formID: 0x20, editorID: "MUSExplore", flags: 0x000C, tracks: [0x100]
                ),
                MusicFixture.TypeSpec(formID: 0x40, editorID: "MUSFight", tracks: [0x103]),
                MusicFixture.TypeSpec(formID: 0x50, editorID: "MUSSpecialSuccess", tracks: [0x104]),
                MusicFixture.TypeSpec(formID: 0x60, editorID: "MUSDiscoveryTown", tracks: [0x105])
            ],
            tracks: [
                MusicFixture.TrackSpec(formID: 0x100, file: "Music\\explore\\a.xwm"),
                MusicFixture.TrackSpec(formID: 0x103, file: "Music\\combat\\d.xwm"),
                MusicFixture.TrackSpec(formID: 0x104, file: "Music\\special\\e.xwm"),
                MusicFixture.TrackSpec(formID: 0x105, file: "Music\\special\\town.xwm")
            ],
            defaultObjects: [("LUMS", 0x50), ("BTMS", 0x40)]
        )
    }

    @Test func theDefaultObjectsNameTheSpecialMusic() {
        let store = Self.store()
        #expect(store.specialMusic[.levelUp] == FormID(0x50))
        #expect(store.specialMusic[.battle] == FormID(0x40))
        #expect(store.specialMusic[.death] == nil)
    }

    @Test func specialMusicPlaysOnceThenTheInterruptedMusicReturns() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine, musicStore: Self.store())
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        #expect(director.playSpecialMusic(.levelUp) == nil)
        #expect(director.currentStateName == "special")
        let special = try #require(engine.sources.first { $0.name == "music\\special\\e.xwm" })
        #expect(!special.loops)
        engine.stopSource(id: special.id)
        director.tick(deltaTime: 1.0 / 60)
        #expect(director.currentStateName == "exploration")
        #expect(director.currentTrackName == "music\\explore\\a.xwm")
        #expect(director.playSpecialMusic(.death) == .noSpecialMusic("DTMS"))
    }

    @Test func combatUsesTheBattleMusicAndCutsASpecialMoment() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine, musicStore: Self.store())
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        director.playSpecialMusic(.levelUp)
        #expect(director.setCombatActive(true) == nil)
        #expect(director.currentTrackName == "music\\combat\\d.xwm")
        director.setCombatActive(false)
        #expect(director.currentStateName == "exploration")
    }

    @Test func discoveryMusicFollowsTheMarkerTypeAndWaitsOutCombat() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine, musicStore: Self.store())
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        #expect(director.playDiscoveryMusic(markerType: 2) == nil)
        #expect(director.currentTrackName == "music\\special\\town.xwm")
        #expect(
            director.playDiscoveryMusic(markerType: 7) == .unknownMusicType("MUSDiscoveryDungeon")
        )
        director.setCombatActive(true)
        #expect(director.playDiscoveryMusic(markerType: 2) == nil)
        #expect(director.currentTrackName == "music\\combat\\d.xwm")
    }
}
