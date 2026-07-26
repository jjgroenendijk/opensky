// Shared synthetic fixtures for the music selection + director suites: in-code
// MUSC/MUST and REGN plugins, and a director wired to an offline-rendering
// engine with a stubbed file loader. No real audio device, no VFS, no extracted
// game file.

import AVFAudio
import Foundation
@testable import opensky
import Testing

enum MusicFixture {
    /// One synthetic MUSC.
    struct TypeSpec {
        let formID: UInt32
        var editorID = "MUSExplore"
        /// FNAM bits. 0x0004 = cycle tracks, 0x0008 = maintain order,
        /// 0x0001 = plays one selection, 0x0002 = abrupt transition.
        var flags: UInt32 = 0
        /// WNAM fade duration in seconds; nil omits the field.
        var fadeSeconds: Float?
        /// TNAM links in authored order. Zero entries are null separators.
        var tracks: [UInt32] = []
    }

    /// One synthetic MUST.
    struct TrackSpec {
        let formID: UInt32
        var editorID = "Track"
        /// CNAM tag: single track, palette, or silent.
        var type: UInt32 = 0x6ED7_E048
        /// ANAM filename; nil omits the field (a silent or palette track).
        var file: String?
        /// SNAM palette children.
        var children: [UInt32] = []
    }

    static let singleTrackTag: UInt32 = 0x6ED7_E048
    static let paletteTag: UInt32 = 0x23F6_78C3
    static let silentTag: UInt32 = 0xA1A9_C4D5

    static func makeStore(types: [TypeSpec], tracks: [TrackSpec]) -> MusicRecordStore {
        var muscBytes = Data()
        for type in types {
            var fields = ESMFixture.field("EDID", ESMFixture.zstring(type.editorID))
                + ESMFixture.field("FNAM", uint32(type.flags))
            if let fade = type.fadeSeconds {
                var wnam = Data()
                wnam.appendFloat32(fade)
                fields += ESMFixture.field("WNAM", wnam)
            }
            if !type.tracks.isEmpty {
                fields += ESMFixture.field("TNAM", type.tracks.reduce(Data()) { $0 + uint32($1) })
            }
            muscBytes += ESMFixture.record("MUSC", formID: type.formID, data: fields)
        }
        var mustBytes = Data()
        for track in tracks {
            var fields = ESMFixture.field("EDID", ESMFixture.zstring(track.editorID))
                + ESMFixture.field("CNAM", uint32(track.type))
            if let file = track.file {
                fields += ESMFixture.field("ANAM", ESMFixture.zstring(file))
            }
            if !track.children.isEmpty {
                fields += ESMFixture.field(
                    "SNAM", track.children.reduce(Data()) { $0 + uint32($1) }
                )
            }
            mustBytes += ESMFixture.record("MUST", formID: track.formID, data: fields)
        }
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup("MUSC", contents: muscBytes)
            + ESMFixture.topGroup("MUST", contents: mustBytes)
        do {
            return try MusicRecordStore(file: ESMFile(data: plugin))
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }

    /// REGN records carrying only an RDMO music link.
    static func makeWeatherStore(regionMusic: [UInt32: UInt32]) -> WeatherStore {
        var bytes = Data()
        for (regionID, musicID) in regionMusic.sorted(by: { $0.key < $1.key }) {
            let fields = ESMFixture.field("EDID", ESMFixture.zstring("Region\(regionID)"))
                + ESMFixture.field("RDMO", uint32(musicID))
            bytes += ESMFixture.record("REGN", formID: regionID, data: fields)
        }
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup("REGN", contents: bytes)
        do {
            return try WeatherStore(file: ESMFile(data: plugin))
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }

    /// The shape most cases need: one cycling MUSC (`0x20`, two tracks) and one
    /// town MUSC (`0x30`, one track).
    static func makeDefaultStore() -> MusicRecordStore {
        makeStore(
            types: [
                TypeSpec(
                    formID: 0x20,
                    editorID: "MUSExplore",
                    flags: 0x000C, // cycle tracks + maintain order
                    fadeSeconds: 3,
                    tracks: [0x100, 0x101]
                ),
                TypeSpec(
                    formID: 0x30,
                    editorID: "MUSTownWhiterun",
                    flags: 0,
                    tracks: [0x102]
                )
            ],
            tracks: [
                TrackSpec(formID: 0x100, editorID: "TrackA", file: "Music\\explore\\a.xwm"),
                TrackSpec(formID: 0x101, editorID: "TrackB", file: "Music\\explore\\b.xwm"),
                TrackSpec(formID: 0x102, editorID: "TrackC", file: "Music\\town\\c.xwm")
            ]
        )
    }

    static func context(
        cellMusicType: UInt32? = nil,
        regions: [UInt32] = [],
        worldspaceMusicType: UInt32? = nil,
        isInterior: Bool = false
    ) -> MusicContext {
        MusicContext(
            isInterior: isInterior,
            cellMusicType: cellMusicType.map { FormID($0) },
            regions: regions.map { FormID($0) },
            worldspaceMusicType: worldspaceMusicType.map { FormID($0) },
            cellIdentity: 0
        )
    }

    private static func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}

@MainActor
enum MusicDirectorFixture {
    static func makeRunningEngine() throws -> WorldAudioEngine {
        try MusicAudioFixture.makeRunningEngine()
    }

    /// Director over the default store. `missingPaths` fail to load, so a test
    /// can exercise the degrade-to-silence and skip-a-bad-track paths.
    static func makeDirector(
        engine: WorldAudioEngine,
        musicStore: MusicRecordStore? = MusicFixture.makeDefaultStore(),
        weatherStore: WeatherStore? = nil,
        missingPaths: Set<String> = []
    ) -> WorldMusicDirector {
        WorldMusicDirector(
            engine: engine,
            musicStore: musicStore,
            weatherStore: weatherStore,
            fileLoader: { path in
                guard !missingPaths.contains(path) else {
                    throw NSError(domain: "MusicDirectorFixture", code: 2)
                }
                return XWMFixture.file(packetCount: 2)
            }
        )
    }

    /// Ids of the music sources the engine currently holds, in start order.
    static func musicSourceIDs(_ engine: WorldAudioEngine) -> [Int] {
        engine.sources.filter { $0.category == .music }.map(\.id)
    }
}
