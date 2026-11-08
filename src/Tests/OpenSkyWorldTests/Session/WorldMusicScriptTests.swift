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

@MainActor
struct WorldMusicPriorityTests {
    private static func store() -> MusicRecordStore {
        MusicFixture.makeStore(
            types: [
                MusicFixture.TypeSpec(formID: 0x20, tracks: [0x100], priority: 10),
                MusicFixture.TypeSpec(formID: 0x30, tracks: [0x102], priority: 50)
            ],
            tracks: [
                MusicFixture.TrackSpec(formID: 0x100, file: "Music\\explore\\a.xwm"),
                MusicFixture.TrackSpec(formID: 0x102, file: "Music\\town\\c.xwm")
            ]
        )
    }

    @Test func aHigherPriorityTypeKeepsPlayingOverANewerLowerOne() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine, musicStore: Self.store())
        director.addScriptedMusic(FormID(0x20))
        director.addScriptedMusic(FormID(0x30))
        #expect(director.playingScriptedMusic == FormID(0x20))
        #expect(director.currentTrackName == "music\\explore\\a.xwm")

        director.removeScriptedMusic(FormID(0x20))
        #expect(director.currentTrackName == "music\\town\\c.xwm")
    }

    @Test func equalPrioritiesPlayTheNewest() {
        let top = ScriptedMusicStack.top([FormID(1), FormID(2), FormID(3)]) { id in
            id == FormID(3) ? 80 : nil
        }
        #expect(top == FormID(3))
        #expect(ScriptedMusicStack.top([FormID(1), FormID(2)]) { _ in nil } == FormID(2))
    }
}
