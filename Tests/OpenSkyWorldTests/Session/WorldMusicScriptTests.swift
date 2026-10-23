// The scripted music stack (docs/engine/music.md): `MusicType.Add` plays over the
// cell's music, and `Remove` returns to the next scripted type or to the cell.

@testable import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyWorld
import OpenSkyWorldFixtures
import Testing

@MainActor
struct WorldMusicScriptTests {
    @Test func addedMusicPlaysOverTheCellUntilRemoved() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(
            engine: engine, musicStore: MusicFixture.makeDefaultStore()
        )
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        #expect(director.currentTrackName == "music\\explore\\a.xwm")

        #expect(director.addScriptedMusic(FormID(0x30)) == nil)
        #expect(director.currentTrackName == "music\\town\\c.xwm")
        // A new cell is remembered but does not replace the scripted music.
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        #expect(director.currentTrackName == "music\\town\\c.xwm")

        director.removeScriptedMusic(FormID(0x30))
        #expect(director.scriptedMusic.isEmpty)
        #expect(director.currentTrackName == "music\\explore\\a.xwm")
    }

    @Test func removingAnOlderTypeKeepsTheNewestPlaying() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(
            engine: engine, musicStore: MusicFixture.makeDefaultStore()
        )
        director.addScriptedMusic(FormID(0x20))
        director.addScriptedMusic(FormID(0x30))
        director.removeScriptedMusic(FormID(0x20))
        #expect(director.scriptedMusic == [FormID(0x30)])
        #expect(director.currentTrackName == "music\\town\\c.xwm")
        #expect(director.addScriptedMusic(FormID(0x99)) != nil)
    }
}
