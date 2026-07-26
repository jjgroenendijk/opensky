// M9 acceptance against the user's read-only Skyrim SE install (issue #157):
// the real-data half of "a Whiterun walk has door SFX, ambience, and music
// transitioning between interior and exterior". It proves the records the three
// audio subsystems consume actually resolve on the shipped plugin — the
// exterior cell's regions yield an ambient bed and its precedence chain yields a
// playlist, the interior cell's acoustic space yields its own bed and the
// interior music state, and the door on the route yields open and close sound
// descriptors that resolve to real files.
//
// Deliberately no assertion on audible output: playback needs a device and the
// vanilla sound effects are `.wav`, which no decoder here reads yet
// (docs/engine/audio.md). Audible confirmation stays a human step.
//
// Route records are the M4 walk route's (`WalkPathRoute`), on the Whiterun-hold
// approach to Chillfurrow Farm: exterior cell (7,-3), the farmhouse interior,
// and the farmhouse door. Nothing is identified by a guessed FormID — the two
// cells are looked up by editor ID and then checked against the route, and the
// door base comes from the route reference's own `NAME`.
//
// No game-derived bytes are written anywhere: the report goes to gitignored
// `logs/m9-audio-acceptance.log` and names records, paths and counts only.

import Foundation
@testable import opensky
import Testing

struct M9AudioAcceptanceRealDataTests {
    /// Env-gated exactly like `CellRenderRealDataTests`: without
    /// `OPENSKY_DATA_ROOT` the test skips instead of consulting the Steam
    /// default. No Metal device is needed — nothing here renders or decodes.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        dataRoot != nil
    }

    /// Editor IDs of the two route cells. Resolved by name rather than by
    /// FormID, and the exterior one is then checked against the route grid, so
    /// a wrong record cannot pass unnoticed.
    private static let exteriorCellEditorID = "ChillfurrowFarmExterior"
    private static let interiorCellEditorID = "ChillfurrowFarm"

    @Test(.enabled(if: Self.canRun))
    func whiterunExteriorAndInteriorResolveTheirWorldAudio() throws {
        let install = try Install()
        let exterior = try install.verifyExterior()
        let interior = try install.verifyInterior()
        let door = try install.verifyDoor()

        let report = ([exterior, interior, door] as [String]).joined(separator: "\n")
        try Self.write(report)
        print(report)
    }

    /// The install's audio-facing stores plus the four route records, read once.
    private struct Install {
        let fileSystem: VirtualFileSystem
        let soundStore: SoundRecordStore
        let aspcStore: AcousticSpaceStore
        let musicStore: MusicRecordStore
        let weatherStore: WeatherStore
        let file: ESMFile
        let localized: Bool
        let exteriorCell: Cell
        let interiorCell: Cell
        let worldspace: Worldspace
        let doorReference: PlacedReference

        init() throws {
            let root = try #require(M9AudioAcceptanceRealDataTests.dataRoot)
            let plugin = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
            let isLocalized = (try? plugin.pluginHeader().isLocalized) ?? false
            fileSystem = VirtualFileSystem(root: root)
            file = plugin
            localized = isLocalized
            soundStore = SoundRecordStore(file: plugin)
            aspcStore = AcousticSpaceStore(file: plugin)
            musicStore = MusicRecordStore(file: plugin)
            weatherStore = WeatherStore(file: plugin)

            // One walk over the plugin collects every route record; an editor-ID
            // lookup per record would decompress the whole file each time.
            var exterior: Cell?
            var interior: Cell?
            var world: Worldspace?
            var door: PlacedReference?
            ESMWalk.forEachRecord(in: plugin) { record in
                switch record.type {
                case "CELL":
                    let editorID = ESMWalk.editorID(of: record)
                    if editorID == M9AudioAcceptanceRealDataTests.exteriorCellEditorID {
                        exterior = try? Cell(record: record, localized: isLocalized)
                    } else if editorID == M9AudioAcceptanceRealDataTests.interiorCellEditorID {
                        interior = try? Cell(record: record, localized: isLocalized)
                    }
                case "WRLD":
                    if ESMWalk.editorID(of: record) == FirstRenderCell.worldspaceEditorID {
                        world = try? Worldspace(record: record, localized: isLocalized)
                    }
                case "REFR":
                    if record.formID == WalkPathRoute.farmDoor.rawValue {
                        door = try? PlacedReference(record: record)
                    }
                default:
                    break
                }
                return exterior == nil || interior == nil || world == nil || door == nil
            }
            exteriorCell = try #require(exterior, "exterior route cell not found")
            interiorCell = try #require(interior, "interior route cell not found")
            worldspace = try #require(world, "route worldspace not found")
            doorReference = try #require(door, "route door reference not found")
        }

        /// Exterior half: the cell's XCLR regions must yield a resolvable
        /// ambient bed, and the selection precedence chain must yield a playable
        /// exterior playlist whose first track really exists in the archives.
        func verifyExterior() throws -> String {
            let grid = try #require(exteriorCell.grid)
            #expect(grid.x == WalkPathRoute.farmCell.x)
            #expect(grid.y == WalkPathRoute.farmCell.y)
            #expect(!exteriorCell.regions.isEmpty)

            let bed = AmbienceBed.resolve(
                context: AmbienceContext(
                    regions: exteriorCell.regions, acousticSpace: nil, isInterior: false
                ),
                weatherStore: weatherStore,
                aspcStore: aspcStore
            )
            #expect(!bed.entries.isEmpty, "the exterior regions author no ambient bed")
            let bedPaths = resolvedPaths(bed)
            #expect(!bedPaths.isEmpty, "no ambient bed sound resolved to a file")

            let selection = MusicSelection.resolve(
                context: MusicContext(
                    isInterior: false,
                    cellMusicType: exteriorCell.musicType,
                    regions: exteriorCell.regions,
                    worldspaceMusicType: worldspace.musicType,
                    cellIdentity: exteriorCell.formID.rawValue
                ),
                musicStore: musicStore,
                weatherStore: weatherStore
            )
            #expect(!selection.isSilent, "the exterior cell resolves no playlist")
            #expect(selection.state != .interior)
            let track = try #require(selection.tracks.first)
            let located = try #require(
                locate(track: track.path), "the playlist's first track is in no archive"
            )
            #expect(
                located.key.hasSuffix(".xwm"),
                "the resolver did not reach a shipped .xwm asset"
            )
            let framed = try XWMFile(data: located.data)
            #expect(framed.packetCount > 0)
            // Every other track in the playlist must resolve the same way, so
            // the fallback is proven over the whole selection rather than one
            // lucky record.
            let resolvedTracks = selection.tracks.filter { locate(track: $0.path) != nil }
            #expect(
                resolvedTracks.count == selection.tracks.count,
                "not every playlist track resolves to a shipped file"
            )

            return """
            [INFO] exterior \(exteriorCell.formID.description) \
            \(M9AudioAcceptanceRealDataTests.exteriorCellEditorID) (\(grid.x),\(grid.y)): \
            \(exteriorCell.regions.count) regions, bed of \(bed.entries.count) sounds
            [INFO] exterior bed files: \(bedPaths.joined(separator: ", "))
            [INFO] exterior music: \(selection.editorID ?? "?") \
            (\(selection.musicType?.description ?? "?")), state \(selection.state.displayName), \
            \(selection.tracks.count) tracks (\(resolvedTracks.count) resolved), crossfade \
            \(selection.crossfadeSeconds) s
            [INFO] exterior first track: \(track.path) -> \(located.key) — \
            \(framed.packetCount) packets, \(framed.codec.sampleRate) Hz, \
            \(framed.codec.channelCount) ch
            \(Self.extensionNote(anam: track.path, key: located.key))
            """
        }

        /// Reads a MUST track out of the archives through the engine's own
        /// resolver — the same `MusicRecordStore.loadAudioFile` the runtime
        /// director calls, with the VFS as its loader. Vanilla `MUST ANAM`
        /// names a `.wav` while the shipped asset is the `.xwm` sibling, so
        /// this is the assertion that the fallback for issue #246 works on the
        /// real install rather than only on synthetic fixtures.
        private func locate(track path: String) -> (key: String, data: Data)? {
            try? MusicRecordStore.loadAudioFile(at: path) { key in
                try fileSystem.contents(forPath: key)
            }
        }

        private static func extensionNote(anam: String, key: String) -> String {
            guard anam != key else {
                return "[INFO] MUST ANAM names the shipped asset directly"
            }
            return "[INFO] MUST ANAM names \(anam); the archives ship \(key), "
                + "which the engine resolver found through the .xwm sibling rule"
        }

        /// Interior half: the cell's XCAS acoustic space must decode, and the
        /// same context must derive the interior music state from a playable
        /// interior playlist.
        func verifyInterior() throws -> String {
            #expect(interiorCell.isInterior)
            #expect(interiorCell.formID == WalkPathRoute.farmInterior)
            let acousticSpaceID = try #require(
                interiorCell.acousticSpace, "the interior cell authors no XCAS"
            )
            let space = try #require(
                aspcStore.acousticSpace(acousticSpaceID), "XCAS names no ASPC record"
            )
            let bed = AmbienceBed.resolve(
                context: AmbienceContext(
                    regions: [], acousticSpace: acousticSpaceID, isInterior: true
                ),
                weatherStore: weatherStore,
                aspcStore: aspcStore
            )
            let bedPaths = resolvedPaths(bed)

            let selection = MusicSelection.resolve(
                context: MusicContext(
                    isInterior: true,
                    cellMusicType: interiorCell.musicType,
                    regions: [],
                    worldspaceMusicType: nil,
                    cellIdentity: interiorCell.formID.rawValue
                ),
                musicStore: musicStore,
                weatherStore: weatherStore
            )
            #expect(selection.state == .interior)
            #expect(!selection.isSilent, "the interior cell resolves no playlist")

            return """
            [INFO] interior \(interiorCell.formID.description) \
            \(M9AudioAcceptanceRealDataTests.interiorCellEditorID): ASPC \
            \(space.formID.description) \(space.editorID ?? "?"), ambient \
            \(space.ambientSound?.description ?? "none"), borrowed region \
            \(space.borrowedRegion?.description ?? "none")
            [INFO] interior bed: \(bed.entries.count) sounds\
            \(bedPaths.isEmpty ? "" : " — " + bedPaths.joined(separator: ", "))
            [INFO] interior music: \(selection.editorID ?? "?") \
            (\(selection.musicType?.description ?? "?")), state \(selection.state.displayName), \
            \(selection.tracks.count) tracks
            """
        }

        /// Door half: the route reference's base must be a DOOR carrying both an
        /// activation and a close sound, and both must resolve to real files.
        func verifyDoor() throws -> String {
            let baseRecord = try #require(
                ESMWalk.record(withFormID: doorReference.base.rawValue, in: file)
            )
            let base = try ModelBase(record: baseRecord, localized: localized)
            #expect(base.recordType == "DOOR")
            let sounds = try #require(base.sounds, "the route door authors no sounds")
            let activation = try #require(sounds.activation, "no DOOR SNAM open sound")
            let close = try #require(sounds.close, "no DOOR ANAM close sound")
            let openPaths = try #require(paths(of: activation))
            let closePaths = try #require(paths(of: close))
            #expect(!openPaths.isEmpty)
            #expect(!closePaths.isEmpty)

            return """
            [INFO] door \(doorReference.formID.description) -> base \
            \(base.formID.description) \(base.editorID ?? "?") (\(base.recordType))
            [INFO] door open \(activation.description): \(openPaths.joined(separator: ", "))
            [INFO] door close \(close.description): \(closePaths.joined(separator: ", "))
            """
        }

        /// Every file path the bed's sounds resolve to, skipping entries the
        /// store cannot resolve (reported by the count difference in the log).
        private func resolvedPaths(_ bed: AmbienceBed) -> [String] {
            bed.entries.flatMap { paths(of: $0.sound) ?? [] }
        }

        /// File paths behind one SNDR/SOUN reference, or nil when it does not
        /// resolve at all.
        private func paths(of sound: FormID) -> [String]? {
            try? soundStore.resolveAny(sound).filePaths
        }
    }

    private static var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs")
    }

    private static func write(_ report: String) throws {
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try report.write(
            to: logs.appending(path: "m9-audio-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
    }
}
