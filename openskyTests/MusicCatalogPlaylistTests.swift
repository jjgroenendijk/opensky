// Music playlist assembly: MUSC flag handling, palette expansion, playable
// track filtering, deterministic ordering, the crossfade duration, and the
// selection equality the director uses as its restart guard. Split from
// MusicCatalogTests for the strict type-length limit; same synthetic fixtures.

@testable import opensky
import Testing

struct MusicCatalogPlaylistTests {
    // MARK: - Flags and ordering

    @Test func cycleTracksWithMaintainOrderKeepsTheAuthoredOrder() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x20),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: nil
        )
        #expect(selection.advance == .cycle)
        #expect(selection.tracks.map(\.editorID) == ["TrackA", "TrackB"])
    }

    @Test func playsOneSelectionTruncatesTheListAndStops() {
        let store = MusicFixture.makeStore(
            types: [MusicFixture.TypeSpec(
                formID: 0x40, flags: 0x0001, tracks: [0x100, 0x101]
            )],
            tracks: [
                MusicFixture.TrackSpec(formID: 0x100, editorID: "One", file: "Music\\a.xwm"),
                MusicFixture.TrackSpec(formID: 0x101, editorID: "Two", file: "Music\\b.xwm")
            ]
        )
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x40),
            musicStore: store,
            weatherStore: nil
        )
        #expect(selection.advance == .stopAfterOne)
        #expect(selection.tracks.count == 1)
    }

    @Test func noCycleFlagRepeatsASingleTrack() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x30),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: nil
        )
        #expect(selection.advance == .repeatCurrent)
        #expect(selection.tracks.count == 1)
    }

    /// Without "maintain track order" the order is shuffled, but from a seed
    /// derived from the context — so it is stable across runs and differs
    /// between two cells that carry the same playlist.
    @Test func trackOrderIsDeterministicAndContextDependent() {
        let store = MusicFixture.makeStore(
            types: [MusicFixture.TypeSpec(
                formID: 0x40, flags: 0x0004, tracks: [0x100, 0x101, 0x102, 0x103]
            )],
            tracks: (0 ..< 4).map { index in
                MusicFixture.TrackSpec(
                    formID: 0x100 + UInt32(index),
                    editorID: "T\(index)",
                    file: "Music\\t\(index).xwm"
                )
            }
        )
        func order(cellIdentity: UInt32) -> [String?] {
            MusicSelection.resolve(
                context: MusicContext(
                    isInterior: false,
                    cellMusicType: FormID(0x40),
                    regions: [],
                    worldspaceMusicType: nil,
                    cellIdentity: cellIdentity
                ),
                musicStore: store,
                weatherStore: nil
            ).tracks.map(\.editorID)
        }
        let first = order(cellIdentity: 1)
        #expect(first == order(cellIdentity: 1), "same context must reproduce the order")
        #expect(first.count == 4)
        #expect(Set(first) == Set(["T0", "T1", "T2", "T3"]), "shuffle must not drop tracks")
        // The two seeds below are known to disagree; a shuffle that always
        // produced the authored order would fail here.
        #expect(first != order(cellIdentity: 7))
    }

    // MARK: - Palettes and playability

    @Test func paletteTracksExpandIntoTheirChildren() {
        let store = MusicFixture.makeStore(
            types: [MusicFixture.TypeSpec(
                formID: 0x40, flags: 0x000C, tracks: [0x100]
            )],
            tracks: [
                MusicFixture.TrackSpec(
                    formID: 0x100,
                    editorID: "Palette",
                    type: MusicFixture.paletteTag,
                    children: [0x101, 0x102]
                ),
                MusicFixture.TrackSpec(formID: 0x101, editorID: "Leaf1", file: "Music\\a.xwm"),
                MusicFixture.TrackSpec(formID: 0x102, editorID: "Leaf2", file: "Music\\b.xwm")
            ]
        )
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x40),
            musicStore: store,
            weatherStore: nil
        )
        #expect(selection.tracks.map(\.editorID) == ["Leaf1", "Leaf2"])
    }

    @Test func selfReferencingPaletteTerminates() {
        let store = MusicFixture.makeStore(
            types: [MusicFixture.TypeSpec(formID: 0x40, flags: 0x000C, tracks: [0x100])],
            tracks: [
                MusicFixture.TrackSpec(
                    formID: 0x100,
                    editorID: "Loop",
                    type: MusicFixture.paletteTag,
                    children: [0x100, 0x101]
                ),
                MusicFixture.TrackSpec(formID: 0x101, editorID: "Leaf", file: "Music\\a.xwm")
            ]
        )
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x40),
            musicStore: store,
            weatherStore: nil
        )
        #expect(selection.tracks.map(\.editorID) == ["Leaf"])
    }

    @Test func silentAndUnplayableTracksAreDropped() {
        let store = MusicFixture.makeStore(
            types: [MusicFixture.TypeSpec(formID: 0x40, flags: 0x000C, tracks: [0x100, 0x101])],
            tracks: [
                MusicFixture.TrackSpec(
                    formID: 0x100, editorID: "Silence", type: MusicFixture.silentTag
                ),
                MusicFixture.TrackSpec(formID: 0x101, editorID: "Audible", file: "Music\\a.xwm")
            ]
        )
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x40),
            musicStore: store,
            weatherStore: nil
        )
        #expect(selection.tracks.map(\.editorID) == ["Audible"])
        #expect(selection.tracks.map(\.path) == ["music\\a.xwm"])
    }

    /// A playlist whose every track is unplayable resolves to silence rather
    /// than to a selection the director could never start.
    @Test func playlistWithNoPlayableTrackIsSilent() {
        let store = MusicFixture.makeStore(
            types: [MusicFixture.TypeSpec(formID: 0x40, tracks: [0x100])],
            tracks: [MusicFixture.TrackSpec(
                formID: 0x100, type: MusicFixture.silentTag
            )]
        )
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x40),
            musicStore: store,
            weatherStore: nil
        )
        #expect(selection.isSilent)
        #expect(selection.musicType == FormID(0x40), "the winner is still reported")
    }

    // MARK: - Crossfade duration

    @Test func crossfadeComesFromTheMusicTypeFadeDuration() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x20),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: nil
        )
        #expect(selection.crossfadeSeconds == 3)
    }

    @Test func crossfadeFallsBackToTheDefaultWhenUnauthored() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x30),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: nil
        )
        #expect(selection.crossfadeSeconds == MusicSelection.defaultCrossfadeSeconds)
    }

    @Test func abruptTransitionForcesAHardCut() {
        let store = MusicFixture.makeStore(
            types: [MusicFixture.TypeSpec(
                formID: 0x40, flags: 0x0002, fadeSeconds: 5, tracks: [0x100]
            )],
            tracks: [MusicFixture.TrackSpec(formID: 0x100, file: "Music\\a.xwm")]
        )
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x40),
            musicStore: store,
            weatherStore: nil
        )
        #expect(selection.crossfadeSeconds == 0)
    }

    // MARK: - Equality (the director's restart guard)

    @Test func twoContextsSelectingTheSamePlaylistCompareEqual() {
        let store = MusicFixture.makeDefaultStore()
        let viaCell = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x20),
            musicStore: store,
            weatherStore: nil
        )
        let viaWorld = MusicSelection.resolve(
            context: MusicFixture.context(worldspaceMusicType: 0x20),
            musicStore: store,
            weatherStore: nil
        )
        #expect(viaCell == viaWorld)
    }
}
