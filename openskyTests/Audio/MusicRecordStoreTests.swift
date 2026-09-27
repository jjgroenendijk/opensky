// MusicRecordStore indexing, MUSC -> MUST expansion, and music path
// canonicalization. Fixtures are synthetic plugins built in code.

import Foundation
@testable import opensky
import Testing

struct MusicRecordStoreTests {
    @Test func indexesMusicTypesAndTracks() throws {
        let store = try makeStore()
        #expect(store.musicTypes.count == 1)
        #expect(store.musicTracks.count == 2)
        #expect(store.musicType(FormID(0x20))?.editorID == "MUSExplore")
        #expect(store.musicTrack(FormID(0x100))?.editorID == "Track1")
        #expect(store.musicType(FormID(0x999)) == nil)
        #expect(store.musicTrack(FormID(0x999)) == nil)
    }

    @Test func resolveKeepsAuthoredOrderAndDropsDanglingLinks() throws {
        let store = try makeStore()
        let resolved = try store.resolve(musicType: FormID(0x20))
        #expect(resolved.musicType.formID == FormID(0x20))
        // TNAM order is 0x101, null, 0x100, 0x777 (dangling).
        #expect(resolved.tracks.map(\.formID) == [FormID(0x101), FormID(0x100)])
    }

    @Test func resolveThrowsForMissingMusicType() throws {
        let store = try makeStore()
        #expect(throws: MusicResolveError.musicTypeNotFound(FormID(0x999))) {
            _ = try store.resolve(musicType: FormID(0x999))
        }
    }

    @Test func emptyPluginYieldsEmptyStore() throws {
        let store = try MusicRecordStore(file: ESMFile(data: ESMFixture.tes4()))
        #expect(store.musicTypes.isEmpty)
        #expect(store.musicTracks.isEmpty)
    }

    @Test func canonicalizesMusicPaths() {
        #expect(
            MusicRecordStore.canonicalMusicPath("Music\\Explore\\mus_01.xwm")
                == "music\\explore\\mus_01.xwm"
        )
        // Bare filename gets the music root prefixed.
        #expect(MusicRecordStore.canonicalMusicPath("mus_01.xwm") == "music\\mus_01.xwm")
        // Data-rooted form drops the outer root.
        #expect(
            MusicRecordStore.canonicalMusicPath("Data\\Music\\mus_01.xwm")
                == "music\\mus_01.xwm"
        )
        // Forward slashes normalize to the VFS separator.
        #expect(MusicRecordStore.canonicalMusicPath("Music/Dungeon/a.xwm")
            == "music\\dungeon\\a.xwm")
    }

    @Test func rejectsVolumePaths() {
        #expect(MusicRecordStore.canonicalMusicPath("C:\\Music\\mus.xwm") == nil)
        #expect(MusicRecordStore.canonicalMusicPath("") == nil)
        #expect(MusicRecordStore.canonicalMusicPath("Music\\..\\mus.xwm") == nil)
    }

    /// The vanilla authoring form: a leading separator marks a root-relative
    /// path, not a volume, so it is stripped like any other `Data\` root.
    @Test func acceptsSeparatorLedDataRootedPaths() {
        #expect(
            MusicRecordStore.canonicalMusicPath("\\Data\\Music\\Combat\\MUS_Combat_01.wav")
                == "music\\combat\\mus_combat_01.wav"
        )
        #expect(MusicRecordStore.canonicalMusicPath("\\Music\\mus.xwm") == "music\\mus.xwm")
        #expect(MusicRecordStore.canonicalMusicPath("/Music/mus.xwm") == "music\\mus.xwm")
    }

    @Test func shippedAudioSiblingSwapsOnlyTheFinalExtension() {
        #expect(
            MusicRecordStore.shippedAudioSibling(of: "music\\explore\\a.wav")
                == "music\\explore\\a.xwm"
        )
        // Already the shipped extension, so there is nothing to fall back to.
        #expect(MusicRecordStore.shippedAudioSibling(of: "music\\explore\\a.xwm") == nil)
        // A dot in a directory name is not an extension.
        #expect(MusicRecordStore.shippedAudioSibling(of: "music\\v1.0\\a") == nil)
        #expect(MusicRecordStore.shippedAudioSibling(of: "music\\a.") == nil)
    }

    @Test func loadAudioFileUsesTheAuthoredNameWhenItResolves() throws {
        let file = try MusicRecordStore.loadAudioFile(at: "music\\a.wav") { path in
            #expect(path == "music\\a.wav")
            return Data([1, 2, 3])
        }
        #expect(file.key == "music\\a.wav")
        #expect(file.data == Data([1, 2, 3]))
    }

    /// The vanilla case: the ANAM `.wav` is absent and the `.xwm` sibling is
    /// what the archives ship.
    @Test func loadAudioFileFallsBackToTheShippedSibling() throws {
        var attempted: [String] = []
        let file = try MusicRecordStore.loadAudioFile(at: "music\\a.wav") { path in
            attempted.append(path)
            guard path == "music\\a.xwm" else {
                throw VFSError.fileNotFound(path: path)
            }
            return Data([4, 5])
        }
        #expect(attempted == ["music\\a.wav", "music\\a.xwm"])
        #expect(file.key == "music\\a.xwm")
        #expect(file.data == Data([4, 5]))
    }

    @Test func loadAudioFileRethrowsWhenNeitherNameResolves() {
        #expect(throws: VFSError.fileNotFound(path: "music\\a.wav")) {
            _ = try MusicRecordStore.loadAudioFile(at: "music\\a.wav") { path in
                throw VFSError.fileNotFound(path: path)
            }
        }
    }

    @Test func audioPathsCoverTrackThenFinale() throws {
        let store = try makeStore()
        let track = try #require(store.musicTrack(FormID(0x100)))
        #expect(store.audioPaths(for: track) == [
            "music\\explore\\mus_01.xwm",
            "music\\explore\\mus_finale.xwm"
        ])
        let silent = try #require(store.musicTrack(FormID(0x101)))
        #expect(store.audioPaths(for: silent).isEmpty)
    }

    // MARK: - Fixture

    private func makeStore() throws -> MusicRecordStore {
        var pnam = Data()
        pnam.appendUInt16(5)
        pnam.appendUInt16(200)
        var wnam = Data()
        wnam.appendFloat32(1.5)
        let muscFields = ESMFixture.field("EDID", ESMFixture.zstring("MUSExplore"))
            + ESMFixture.field("FNAM", uint32(0x0004))
            + ESMFixture.field("PNAM", pnam)
            + ESMFixture.field("WNAM", wnam)
            + ESMFixture.field(
                "TNAM", uint32(0x101) + uint32(0) + uint32(0x100) + uint32(0x777)
            )

        let trackOne = ESMFixture.field("EDID", ESMFixture.zstring("Track1"))
            + ESMFixture.field("CNAM", uint32(0x6ED7_E048))
            + ESMFixture.field("ANAM", ESMFixture.zstring("Music\\Explore\\mus_01.xwm"))
            + ESMFixture.field("BNAM", ESMFixture.zstring("Music\\Explore\\mus_finale.xwm"))
        var fltv = Data()
        fltv.appendFloat32(8)
        let trackTwo = ESMFixture.field("EDID", ESMFixture.zstring("Track2"))
            + ESMFixture.field("CNAM", uint32(0xA1A9_C4D5))
            + ESMFixture.field("FLTV", fltv)

        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup("MUSC", contents: ESMFixture.record(
                "MUSC", formID: 0x20, data: muscFields
            ))
            + ESMFixture.topGroup("MUST", contents: ESMFixture.record(
                "MUST", formID: 0x100, data: trackOne
            ) + ESMFixture.record("MUST", formID: 0x101, data: trackTwo))
        return try MusicRecordStore(file: ESMFile(data: plugin))
    }

    private func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
