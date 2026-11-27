// The director waits out a silent track, then starts the next track of a cycling playlist.

@testable import OpenSkyAudio
import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldInterface
import Testing

@MainActor
struct WorldMusicSilenceTests {
    @Test func silentTrackHoldsThenTheNextTrackStarts() throws {
        let store = MusicFixture.makeStore(
            types: [MusicFixture.TypeSpec(formID: 0x40, flags: 0x000C, tracks: [0x100, 0x101])],
            tracks: [
                MusicFixture.TrackSpec(
                    formID: 0x100, editorID: "Silence", type: MusicFixture.silentTag, duration: 5
                ),
                MusicFixture.TrackSpec(formID: 0x101, editorID: "Audible", file: "Music\\a.xwm")
            ]
        )
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine, musicStore: store)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x40))
        #expect(MusicDirectorFixture.musicSourceIDs(engine).isEmpty)
        director.tick(deltaTime: 4)
        #expect(MusicDirectorFixture.musicSourceIDs(engine).isEmpty)
        director.tick(deltaTime: 1.5)
        #expect(MusicDirectorFixture.musicSourceIDs(engine).count == 1)
    }
}
