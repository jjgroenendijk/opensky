// Shared synthetic fixtures for the music selection + director suites: in-code
// MUSC/MUST and REGN plugins, and a director wired to an offline-rendering
// engine with a stubbed file loader. No real audio device, no VFS, no extracted
// game file.

import AVFAudio
@testable import FormatsTesting
import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

public enum MusicFixture {
    /// One synthetic MUSC.
    public struct TypeSpec {
        public let formID: UInt32
        public var editorID = "MUSExplore"
        /// FNAM bits. 0x0004 = cycle tracks, 0x0008 = maintain order,
        /// 0x0001 = plays one selection, 0x0002 = abrupt transition.
        public var flags: UInt32 = 0
        /// WNAM fade duration in seconds; nil omits the field.
        public var fadeSeconds: Float?
        /// TNAM links in authored order. Zero entries are null separators.
        public var tracks: [UInt32] = []

        public init(
            formID: UInt32,
            editorID: String = "MUSExplore",
            flags: UInt32 = 0,
            fadeSeconds: Float? = nil,
            tracks: [UInt32] = []
        ) {
            self.formID = formID
            self.editorID = editorID
            self.flags = flags
            self.fadeSeconds = fadeSeconds
            self.tracks = tracks
        }
    }

    /// One synthetic MUST.
    public struct TrackSpec {
        public let formID: UInt32
        public var editorID = "Track"
        /// CNAM tag: single track, palette, or silent.
        public var type: UInt32 = 0x6ED7_E048
        /// ANAM filename; nil omits the field (a silent or palette track).
        public var file: String?
        /// SNAM palette children.
        public var children: [UInt32] = []

        public init(
            formID: UInt32,
            editorID: String = "Track",
            type: UInt32 = 0x6ED7_E048,
            file: String? = nil,
            children: [UInt32] = []
        ) {
            self.formID = formID
            self.editorID = editorID
            self.type = type
            self.file = file
            self.children = children
        }
    }

    public static let paletteTag: UInt32 = 0x23F6_78C3
    public static let silentTag: UInt32 = 0xA1A9_C4D5

    public static func makeStore(types: [TypeSpec], tracks: [TrackSpec]) -> MusicRecordStore {
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
    public static func makeWeatherStore(regionMusic: [UInt32: UInt32]) -> WeatherStore {
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
    public static func makeDefaultStore() -> MusicRecordStore {
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

    /// The vanilla authoring shape: one MUSC whose single MUST
    /// names a `\Data\Music\...\*.wav` the archives do not ship. Used with
    /// `MusicDirectorFixture.makeDirector(engine:musicStore:availablePaths:)`
    /// to model an install that holds only the `.xwm` sibling.
    public static func makeWavAuthoredStore() -> MusicRecordStore {
        makeStore(
            types: [TypeSpec(formID: 0x20, editorID: "MUSExploreTundra", tracks: [0x100])],
            tracks: [
                TrackSpec(
                    formID: 0x100,
                    editorID: "TrackWav",
                    file: "\\Data\\Music\\Explore\\MUS_Explore_Day_07.wav"
                )
            ]
        )
    }

    /// Canonical key `makeWavAuthoredStore`'s single track resolves to.
    public static let wavAuthoredPath = "music\\explore\\mus_explore_day_07.wav"
    /// The file such an install actually ships.
    public static let shippedAuthoredPath = "music\\explore\\mus_explore_day_07.xwm"

    public static func context(
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
public enum MusicDirectorFixture {
    /// An offline stereo engine, the same one the OpenSkyAudio suites build.
    public static func makeRunningEngine() throws -> WorldAudioEngine {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        engine.isEnabled = true
        try #require(engine.isRunning, "offline engine failed: \(engine.unavailableReason ?? "")")
        return engine
    }

    /// Director over the default store. `missingPaths` fail to load, so a test
    /// can exercise the degrade-to-silence and skip-a-bad-track paths.
    public static func makeDirector(
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

    /// Director whose loader serves exactly `availablePaths` and throws
    /// `VFSError.fileNotFound` for everything else, so a test can model an
    /// install that ships only some of the names the records author.
    public static func makeDirector(
        engine: WorldAudioEngine,
        musicStore: MusicRecordStore,
        availablePaths: Set<String>
    ) -> WorldMusicDirector {
        WorldMusicDirector(
            engine: engine,
            musicStore: musicStore,
            weatherStore: nil,
            fileLoader: { path in
                guard availablePaths.contains(path) else {
                    throw VFSError.fileNotFound(path: path)
                }
                return XWMFixture.file(packetCount: 2)
            }
        )
    }

    /// Ids of the music sources the engine currently holds, in start order.
    public static func musicSourceIDs(_ engine: WorldAudioEngine) -> [Int] {
        engine.sources.filter { $0.category == .music }.map(\.id)
    }
}
