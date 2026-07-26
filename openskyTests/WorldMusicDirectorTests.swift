// WorldMusicDirector runtime behaviour: start, crossfade on selection change,
// playlist advance, the enable toggle round-trip, silent degradation, and the
// live-source-derived readout. Offline manual rendering only — no output
// device, no decode-queue timing, explicit frame deltas.

@testable import opensky
import Testing

@MainActor
struct WorldMusicDirectorTests {
    // MARK: - Start

    @Test func firstContextStartsTheSelectedTrackFadingIn() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))

        let ids = MusicDirectorFixture.musicSourceIDs(engine)
        #expect(ids.count == 1)
        let source = try #require(engine.sources.first { $0.id == ids[0] })
        #expect(source.name == "music\\explore\\a.xwm")
        #expect(source.routing == .nonPositional)
        // Music starts silent and ramps up over the MUSC fade duration.
        #expect(source.fadeGain == 0)
        #expect(engine.isFading(id: source.id))
        #expect(director.currentStateName == "exploration")
        #expect(director.currentTrackName == "music\\explore\\a.xwm")
        #expect(director.currentMusicDescription.hasPrefix("MUSExplore"))
        #expect(director.lastMusicError == nil)
    }

    @Test func aContextResolvingToTheSameSelectionDoesNotRestart() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        let first = MusicDirectorFixture.musicSourceIDs(engine)
        // A neighbouring cell with the same playlist, reached by a different
        // link in the chain, must not interrupt the track.
        director.handleMusicContext(MusicFixture.context(worldspaceMusicType: 0x20))
        #expect(MusicDirectorFixture.musicSourceIDs(engine) == first)
    }

    // MARK: - Crossfade

    @Test func selectionChangeCrossfadesOutgoingOutAndIncomingIn() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        let outgoing = try #require(MusicDirectorFixture.musicSourceIDs(engine).first)
        // Finish the fade-in so the outgoing ramp starts from full gain.
        engine.advanceFades(deltaTime: 3)
        #expect(engine.fadeGain(of: outgoing) == 1)

        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x30))
        let ids = MusicDirectorFixture.musicSourceIDs(engine)
        #expect(ids.count == 2, "both tracks sound during the crossfade")
        let incoming = try #require(ids.last)
        #expect(engine.fadeGain(of: incoming) == 0)
        #expect(engine.isFading(id: incoming))
        #expect(engine.isFading(id: outgoing))

        // Halfway: the ramps are opposite and neither source has been dropped.
        engine.advanceFades(deltaTime: MusicSelection.defaultCrossfadeSeconds / 2)
        let outgoingGain = try #require(engine.fadeGain(of: outgoing))
        let incomingGain = try #require(engine.fadeGain(of: incoming))
        #expect(abs(outgoingGain - 0.5) < 0.05)
        #expect(abs(incomingGain - 0.5) < 0.05)

        // End of the window: the outgoing source retired itself, the incoming
        // one is at full gain.
        engine.advanceFades(deltaTime: MusicSelection.defaultCrossfadeSeconds)
        #expect(!engine.sources.contains { $0.id == outgoing })
        #expect(engine.fadeGain(of: incoming) == 1)
        #expect(director.currentStateName == "town")
    }

    @Test func abruptTransitionCutsWithoutARamp() throws {
        let store = MusicFixture.makeStore(
            types: [MusicFixture.TypeSpec(
                formID: 0x40, flags: 0x0002, tracks: [0x100]
            )],
            tracks: [MusicFixture.TrackSpec(formID: 0x100, file: "Music\\a.xwm")]
        )
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine, musicStore: store)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x40))
        let id = try #require(MusicDirectorFixture.musicSourceIDs(engine).first)
        #expect(engine.fadeGain(of: id) == 1)
        #expect(!engine.isFading(id: id))
    }

    // MARK: - Playlist advance

    @Test func playlistAdvancesWhenTheCurrentTrackFinishes() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        let first = try #require(engine.sources.first)
        #expect(!first.loops, "a cycling playlist must let its tracks end")

        // The engine retires a stream that reached its end; simulate exactly
        // that, then drive one frame.
        engine.stopSource(id: first.id)
        director.tick(deltaTime: 1.0 / 60)
        let names = MusicDirectorFixture.musicSourceIDs(engine)
            .compactMap { id in engine.sources.first { $0.id == id }?.name }
        #expect(names == ["music\\explore\\b.xwm"])

        // End of list wraps back to the first track.
        let second = try #require(engine.sources.first)
        engine.stopSource(id: second.id)
        director.tick(deltaTime: 1.0 / 60)
        #expect(director.currentTrackName == "music\\explore\\a.xwm")
    }

    @Test func aRepeatingSelectionLoopsInTheEngineInsteadOfAdvancing() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x30))
        let source = try #require(engine.sources.first)
        #expect(source.loops)

        engine.stopSource(id: source.id)
        director.tick(deltaTime: 1.0 / 60)
        #expect(engine.sources.isEmpty, "nothing to advance to")
        #expect(director.currentMusicDescription == "none")
    }

    @Test func tickAccumulatesElapsedTimeOnlyWhileATrackPlays() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        director.tick(deltaTime: 0.5)
        director.tick(deltaTime: 0.5)
        #expect(abs(director.currentTrackElapsedSeconds - 1) < 1e-5)
        // A paused frame passes a zero delta, so the readout freezes.
        director.tick(deltaTime: 0)
        #expect(abs(director.currentTrackElapsedSeconds - 1) < 1e-5)
    }

    // MARK: - Enable toggle

    @Test func disablingStopsMusicAndEnablingRestartsTheRememberedSelection() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        #expect(engine.sources.count == 1)

        director.musicEnabled = false
        #expect(engine.sources.isEmpty, "switching off stops now, it does not fade")
        #expect(director.currentMusicDescription == "none")

        director.musicEnabled = true
        #expect(director.currentTrackName == "music\\explore\\a.xwm")
    }

    @Test func aContextArrivingWhileDisabledStartsOnEnable() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.musicEnabled = false
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x30))
        #expect(engine.sources.isEmpty)

        director.musicEnabled = true
        #expect(director.currentTrackName == "music\\town\\c.xwm")
    }

    // MARK: - Degradation

    @Test func absentMusicStoreDegradesToSilence() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine, musicStore: nil)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        #expect(engine.sources.isEmpty)
        #expect(director.currentMusicDescription == "none")
        #expect(director.selectableMusicTypeNames.isEmpty)
        #expect(director.forcePlayMusicType(named: "MUSExplore") == "no music data")
    }

    @Test func anUnloadableTrackIsSkippedForTheNextOneInThePlaylist() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(
            engine: engine, missingPaths: ["music\\explore\\a.xwm"]
        )
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        #expect(director.currentTrackName == "music\\explore\\b.xwm")
    }

    @Test func aPlaylistWithNoLoadableTrackFallsSilentWithAReason() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(
            engine: engine,
            missingPaths: ["music\\explore\\a.xwm", "music\\explore\\b.xwm"]
        )
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        #expect(engine.sources.isEmpty)
        #expect(director.lastMusicError != nil)
    }

    @Test func stopMusicRetiresTheCurrentTrack() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        director.stopMusic()
        // The fade-out is in flight until the ramp completes.
        engine.advanceFades(deltaTime: MusicSelection.defaultCrossfadeSeconds)
        #expect(engine.sources.isEmpty)
        #expect(director.currentMusicDescription == "none")
    }

    // MARK: - Readout + force control

    @Test func readoutIsDerivedFromLiveSources() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))
        #expect(director.currentMusicDescription != "none")

        // The engine retired everything behind the director's back.
        engine.stopAllSources()
        #expect(director.currentMusicDescription == "none")
        #expect(director.currentTrackName == nil)
    }

    @Test func forcePlayCrossfadesToTheNamedMusicType() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        #expect(director.selectableMusicTypeNames == ["MUSExplore", "MUSTownWhiterun"])
        director.handleMusicContext(MusicFixture.context(cellMusicType: 0x20))

        #expect(director.forcePlayMusicType(named: "MUSTownWhiterun") == nil)
        #expect(director.currentTrackName == "music\\town\\c.xwm")
        // The forced selection is remembered, so a toggle restarts it rather
        // than reverting to the streamed context.
        director.musicEnabled = false
        director.musicEnabled = true
        #expect(director.currentTrackName == "music\\town\\c.xwm")
    }

    @Test func forcePlayReportsAnUnknownName() throws {
        let engine = try MusicDirectorFixture.makeRunningEngine()
        let director = MusicDirectorFixture.makeDirector(engine: engine)
        #expect(director.forcePlayMusicType(named: "MUSNope") == "unknown music type MUSNope")
    }
}
