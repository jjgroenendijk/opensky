// Music selection: the CELL -> REGN -> WRLD precedence chain and the three
// derived states. Playlist assembly (flags, palettes, ordering, crossfade) is
// covered by MusicCatalogPlaylistTests. Pure value logic — no engine, no audio
// device. Fixtures are synthetic plugins built in code
// (openskyTests/WorldMusicFixtures.swift).

@testable import opensky
import Testing

struct MusicCatalogTests {
    // MARK: - Precedence

    @Test func cellMusicTypeWinsOverRegionAndWorldspace() {
        let store = MusicFixture.makeDefaultStore()
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(
                cellMusicType: 0x30, regions: [0x200], worldspaceMusicType: 0x20
            ),
            musicStore: store,
            weatherStore: MusicFixture.makeWeatherStore(regionMusic: [0x200: 0x20])
        )
        #expect(selection.editorID == "MUSTownWhiterun")
    }

    @Test func regionMusicTypeWinsOverWorldspace() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(regions: [0x200], worldspaceMusicType: 0x20),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: MusicFixture.makeWeatherStore(regionMusic: [0x200: 0x30])
        )
        #expect(selection.editorID == "MUSTownWhiterun")
    }

    @Test func firstResolvableRegionWinsInRecordOrder() {
        let selection = MusicSelection.resolve(
            // 0x201 has no RDMO at all; 0x202 does.
            context: MusicFixture.context(regions: [0x201, 0x202]),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: MusicFixture.makeWeatherStore(regionMusic: [0x202: 0x20])
        )
        #expect(selection.editorID == "MUSExplore")
    }

    @Test func worldspaceMusicTypeIsTheLastResort() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(worldspaceMusicType: 0x20),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: nil
        )
        #expect(selection.musicType == FormID(0x20))
        #expect(selection.tracks.count == 2)
    }

    /// A dangling override must not silence the world: the chain keeps walking.
    @Test func unresolvableCellOverrideFallsThroughToTheWorldspace() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x999, worldspaceMusicType: 0x20),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: nil
        )
        #expect(selection.editorID == "MUSExplore")
    }

    @Test func absentStoreAndEmptyContextResolveToSilence() {
        let none = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x20),
            musicStore: nil,
            weatherStore: nil
        )
        #expect(none.isSilent)
        #expect(none.displayName == "none")

        let empty = MusicSelection.resolve(
            context: .empty, musicStore: MusicFixture.makeDefaultStore(), weatherStore: nil
        )
        #expect(empty.isSilent)
        #expect(empty.state == .exploration)
    }

    // MARK: - States

    @Test func interiorContextAlwaysDerivesTheInteriorState() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x30, isInterior: true),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: nil
        )
        // Town playlist, but the cell is interior -> interior wins.
        #expect(selection.editorID == "MUSTownWhiterun")
        #expect(selection.state == .interior)
        #expect(selection.state.displayName == "interior")
    }

    @Test func exteriorTownPlaylistDerivesTheTownState() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x30),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: nil
        )
        #expect(selection.state == .town)
    }

    @Test func exteriorNonTownPlaylistDerivesTheExplorationState() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x20),
            musicStore: MusicFixture.makeDefaultStore(),
            weatherStore: nil
        )
        #expect(selection.state == .exploration)
    }

    /// The town inference is an editor-id convention, so a renamed record reads
    /// as exploration. Documented limit, pinned here so it cannot drift.
    @Test func townInferenceIsEditorIDOnly() {
        let store = MusicFixture.makeStore(
            types: [MusicFixture.TypeSpec(
                formID: 0x40, editorID: "CityMusic", tracks: [0x100]
            )],
            tracks: [MusicFixture.TrackSpec(formID: 0x100, file: "Music\\a.xwm")]
        )
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x40),
            musicStore: store,
            weatherStore: nil
        )
        #expect(selection.state == .exploration)
    }

    /// The vanilla authoring form (`\Data\Music\...\*.wav`) stays playable: the
    /// leading separator is a root marker, and the extension mismatch is
    /// resolved at load time, not by the playable filter (issue #246).
    @Test func separatorLedWavTracksSurviveThePlayableFilter() {
        let selection = MusicSelection.resolve(
            context: MusicFixture.context(cellMusicType: 0x20),
            musicStore: MusicFixture.makeWavAuthoredStore(),
            weatherStore: nil
        )
        #expect(!selection.isSilent)
        #expect(selection.tracks.map(\.path) == [MusicFixture.wavAuthoredPath])
    }
}
