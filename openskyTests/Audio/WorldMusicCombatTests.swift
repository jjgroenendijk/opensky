// Combat music (issue #374, roadmap item 15.7, scope point 6): the seam
// `docs/engine/music.md` has been holding open since M9.
//
// The precedence chain is untouched — combat does not join it, because combat is
// a game-system state and not something any record authors. What this suite pins
// is the three properties the seam promised: entering combat selects a
// `MUSCombat...` record directly, leaving combat restores the selection it
// interrupted rather than re-resolving, and a load order with no combat playlist
// leaves the music where it was instead of going silent mid-fight.
//
// Offline manual rendering only, exactly like `WorldMusicDirectorTests`: no
// output device, no decode-queue timing, explicit frame deltas.

@testable import opensky
import Testing

@MainActor
struct WorldMusicCombatTests {
    /// The default store plus one combat playlist, which is the only shape
    /// these tests need that `MusicFixture.makeDefaultStore()` does not carry.
    private static func storeWithCombat() -> MusicRecordStore {
        MusicFixture.makeStore(
            types: [
                MusicFixture.TypeSpec(
                    formID: 0x20,
                    editorID: "MUSExplore",
                    flags: 0x000C,
                    fadeSeconds: 3,
                    tracks: [0x100]
                ),
                MusicFixture.TypeSpec(
                    formID: 0x30,
                    editorID: "MUSTownWhiterun",
                    flags: 0,
                    tracks: [0x102]
                ),
                MusicFixture.TypeSpec(
                    formID: 0x40,
                    editorID: "MUSCombat",
                    flags: 0,
                    tracks: [0x103]
                )
            ],
            tracks: [
                MusicFixture.TrackSpec(
                    formID: 0x100, editorID: "TrackA", file: "Music\\explore\\a.xwm"
                ),
                MusicFixture.TrackSpec(
                    formID: 0x102, editorID: "TrackC", file: "Music\\town\\c.xwm"
                ),
                MusicFixture.TrackSpec(
                    formID: 0x103, editorID: "TrackD", file: "Music\\combat\\d.xwm"
                )
            ]
        )
    }

    @Test func enteringCombatSelectsTheCombatPlaylist() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(
            engine: engine, musicStore: Self.storeWithCombat()
        )
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        #expect(director.currentStateName == "exploration")
        #expect(!director.isCombatMusicActive)

        #expect(director.setCombatActive(true) == nil)

        #expect(director.isCombatMusicActive)
        #expect(director.currentStateName == "combat")
        #expect(director.currentTrackName == "music\\combat\\d.xwm")
    }

    @Test func leavingCombatRestoresTheInterruptedSelection() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(
            engine: engine, musicStore: Self.storeWithCombat()
        )
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        director.setCombatActive(true)
        engine.advanceFades(deltaTime: 5)

        director.setCombatActive(false)

        #expect(!director.isCombatMusicActive)
        #expect(director.currentStateName == "exploration")
        #expect(director.currentTrackName == "music\\explore\\a.xwm")
    }

    @Test func enteringCombatTwiceDoesNotForgetWhereToReturnTo() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(
            engine: engine, musicStore: Self.storeWithCombat()
        )
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        director.setCombatActive(true)
        director.setCombatActive(true)
        engine.advanceFades(deltaTime: 5)

        director.setCombatActive(false)

        #expect(director.currentTrackName == "music\\explore\\a.xwm")
    }

    /// A cell crossed mid-fight updates what leaving combat returns to, rather
    /// than interrupting the fight's own music.
    @Test func aCellCrossedMidFightUpdatesWhatCombatReturnsTo() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(
            engine: engine, musicStore: Self.storeWithCombat()
        )
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        director.setCombatActive(true)
        #expect(director.currentTrackName == "music\\combat\\d.xwm")

        // The player fought their way into a town. The fight's music keeps
        // playing...
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x30))
        #expect(director.currentTrackName == "music\\combat\\d.xwm")

        // ...and leaving combat lands on the town, not on the cell the fight
        // started in.
        director.setCombatActive(false)
        engine.advanceFades(deltaTime: 5)
        #expect(director.currentStateName == "town")
        #expect(director.currentTrackName == "music\\town\\c.xwm")
    }

    /// A load order with no `MUSCombat...` record leaves the music alone and
    /// says why, rather than going silent mid-fight.
    @Test func aLoadOrderWithNoCombatPlaylistLeavesTheMusicAlone() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))

        let failure = director.setCombatActive(true)

        #expect(failure == "no combat music type in the load order")
        #expect(!director.isCombatMusicActive)
        #expect(director.currentTrackName == "music\\explore\\a.xwm")
    }

    /// Leaving combat that never started is a no-op rather than a restart.
    @Test func leavingCombatThatNeverStartedChangesNothing() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(
            engine: engine, musicStore: Self.storeWithCombat()
        )
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        let before = MusicDirectorFixture.musicSourceIDs(engine)

        #expect(director.setCombatActive(false) == nil)

        #expect(MusicDirectorFixture.musicSourceIDs(engine) == before)
    }
}
