// Music playlist selection (M9.2.3, issue #156). Pure value logic over the
// decoded MUSC/MUST records: a context describing where the listener is turns
// into one ordered, playable playlist plus the policy the runtime director
// needs (how it advances, how long the crossfade lasts). No engine, no I/O, no
// randomness that a test cannot reproduce.
//
// Selection precedence, most specific first (docs/engine/music.md):
//   CELL.XCMO -> the first REGN.RDMO among the cell's XCLR regions -> WRLD.ZNAM
//
// The three states the milestone names (exploration, town, interior) are
// derived here, not authored: interior comes from the cell type, town from the
// selected MUSC editor id, and exploration is the fallback. The limits of that
// inference are written down in docs/engine/music.md.

import Foundation

/// Where the listener is, expressed as the only fields music selection reads.
/// The streamer emits a fresh value whenever the center cell changes (exterior
/// recenter, interior enter/exit).
nonisolated struct MusicContext: Equatable, Sendable {
    let isInterior: Bool
    /// CELL.XCMO override; nil when the cell authors none.
    let cellMusicType: FormID?
    /// XCLR REGN FormIDs for the exterior center cell; empty for interiors.
    let regions: [FormID]
    /// WRLD.ZNAM of the owning worldspace; nil for interiors and worldspaces
    /// without one.
    let worldspaceMusicType: FormID?
    /// Stable identity of the cell the context came from (interior CELL FormID
    /// or the packed exterior grid coordinate). Only feeds the deterministic
    /// track pick, so two cells sharing a playlist do not always open on the
    /// same track.
    let cellIdentity: UInt32

    static let empty = MusicContext(
        isInterior: false,
        cellMusicType: nil,
        regions: [],
        worldspaceMusicType: nil,
        cellIdentity: 0
    )

    /// Reproducible seed for the track ordering. Deliberately hand-rolled
    /// (FNV-1a over the fields) because `Hasher` is seeded per process, which
    /// would make the "random" pick differ between two runs of the same scene.
    var seed: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ value: UInt64) {
            var remaining = value
            for _ in 0 ..< 8 {
                hash ^= remaining & 0xFF
                hash &*= 0x0000_0100_0000_01B3
                remaining >>= 8
            }
        }
        mix(isInterior ? 1 : 0)
        mix(UInt64(cellMusicType?.rawValue ?? 0))
        mix(UInt64(worldspaceMusicType?.rawValue ?? 0))
        mix(UInt64(cellIdentity))
        for region in regions {
            mix(UInt64(region.rawValue))
        }
        return hash
    }
}

/// The three music states milestone 9.2.3 names. Derivation and limits:
/// docs/engine/music.md.
nonisolated enum MusicState: String, Equatable, Sendable, CaseIterable {
    /// Any interior CELL, whatever playlist it selects.
    case interior
    /// Exterior whose selected MUSC editor id follows Bethesda's town naming
    /// convention (`MUSTown...`).
    case town
    /// Every other exterior, including one with no playlist at all.
    case exploration

    var displayName: String {
        switch self {
        case .interior: "interior"
        case .town: "town"
        case .exploration: "exploration"
        }
    }
}

/// How the director walks the playlist once a track ends.
nonisolated enum MusicPlaylistAdvance: String, Equatable, Sendable {
    /// MUSC "Plays One Selection": one track, then silence.
    case stopAfterOne
    /// No cycle flag: the single chosen track repeats for as long as the
    /// selection stays current.
    case repeatCurrent
    /// MUSC "Cycle Tracks": advance to the next track at end of file, wrapping
    /// at the end of the list.
    case cycle
}

/// One MUST track reduced to what playback needs.
nonisolated struct PlayableMusicTrack: Equatable, Sendable {
    let formID: FormID
    let editorID: String?
    /// Canonical VFS key of the ANAM stream.
    let path: String
}

/// A resolved playlist: which MUSC won the precedence chain, the tracks it
/// contributes in play order, and the transition policy. Equatable so the
/// director can skip a restart when a new context resolves to the same music.
nonisolated struct MusicSelection: Equatable, Sendable {
    /// Crossfade used when the MUSC authors no WNAM fade duration.
    static let defaultCrossfadeSeconds: Float = 2
    /// Depth bound on palette (MUST-of-MUSTs) expansion.
    static let maximumPaletteDepth = 4

    let state: MusicState
    /// The MUSC that won; nil when nothing was selectable.
    let musicType: FormID?
    let editorID: String?
    /// Play order. Truncated to one entry unless `advance` is `.cycle`.
    let tracks: [PlayableMusicTrack]
    let advance: MusicPlaylistAdvance
    /// Seconds the director crossfades over when swapping to this selection.
    let crossfadeSeconds: Float

    var isSilent: Bool {
        tracks.isEmpty
    }

    /// Label for the panel readout: editor id when the record has one, else the
    /// FormID, else "none".
    var displayName: String {
        if let editorID, !editorID.isEmpty {
            return editorID
        }
        return musicType?.description ?? "none"
    }

    static func silent(state: MusicState) -> MusicSelection {
        MusicSelection(
            state: state,
            musicType: nil,
            editorID: nil,
            tracks: [],
            advance: .stopAfterOne,
            crossfadeSeconds: defaultCrossfadeSeconds
        )
    }

    /// Walks the precedence chain for `context` and resolves the winner. An
    /// absent store, an unresolvable link, or a playlist with no playable file
    /// all degrade to a silent selection rather than throwing.
    static func resolve(
        context: MusicContext,
        musicStore: MusicRecordStore?,
        weatherStore: WeatherStore?
    ) -> MusicSelection {
        let fallbackState: MusicState = context.isInterior ? .interior : .exploration
        guard
            let musicStore,
            let selected = selectMusicType(
                context: context, musicStore: musicStore, weatherStore: weatherStore
            )
        else {
            return .silent(state: fallbackState)
        }
        return resolve(
            musicType: selected,
            musicStore: musicStore,
            isInterior: context.isInterior,
            seed: context.seed
        )
    }

    /// Resolves one named MUSC directly. The panel's force control uses this;
    /// the context path funnels into it after picking a winner.
    static func resolve(
        musicType id: FormID,
        musicStore: MusicRecordStore,
        isInterior: Bool = false,
        seed: UInt64 = 0
    ) -> MusicSelection {
        guard let resolved = try? musicStore.resolve(musicType: id) else {
            return .silent(state: isInterior ? .interior : .exploration)
        }
        let type = resolved.musicType
        let state = derivedState(isInterior: isInterior, editorID: type.editorID)
        let expanded = expandPalettes(resolved.tracks, musicStore: musicStore)
        let playable = playableTracks(expanded, musicStore: musicStore)
        let ordered = type.flags.contains(.maintainTrackOrder)
            ? playable
            : deterministicOrder(playable, seed: seed)
        let advance = advancePolicy(flags: type.flags)
        return MusicSelection(
            state: state,
            musicType: type.formID,
            editorID: type.editorID,
            tracks: advance == .cycle ? ordered : Array(ordered.prefix(1)),
            advance: advance,
            crossfadeSeconds: crossfade(for: type)
        )
    }

    // MARK: - Precedence

    /// CELL.XCMO, then the first REGN.RDMO among the cell's regions (record
    /// order), then WRLD.ZNAM. A link that names a MUSC the store does not
    /// hold is skipped so a broken override cannot silence the world.
    private static func selectMusicType(
        context: MusicContext,
        musicStore: MusicRecordStore,
        weatherStore: WeatherStore?
    ) -> FormID? {
        if let cell = context.cellMusicType, musicStore.musicType(cell) != nil {
            return cell
        }
        for regionID in context.regions {
            guard
                let music = weatherStore?.region(regionID)?.musicType,
                musicStore.musicType(music) != nil
            else { continue }
            return music
        }
        if let world = context.worldspaceMusicType, musicStore.musicType(world) != nil {
            return world
        }
        return nil
    }

    // MARK: - State inference

    /// Bethesda's exterior town playlists are all named `MUSTown<City>`; the
    /// exploration ones are `MUSExplore...`. There is no authored "town" bit
    /// anywhere in the records, so the editor id is the only signal available.
    private static let townEditorIDPrefix = "mustown"

    private static func derivedState(isInterior: Bool, editorID: String?) -> MusicState {
        if isInterior {
            return .interior
        }
        guard let editorID, editorID.lowercased().hasPrefix(townEditorIDPrefix) else {
            return .exploration
        }
        return .town
    }

    // MARK: - Playlist assembly

    private static func advancePolicy(flags: MusicType.Flags) -> MusicPlaylistAdvance {
        if flags.contains(.playsOneSelection) {
            return .stopAfterOne
        }
        return flags.contains(.cycleTracks) ? .cycle : .repeatCurrent
    }

    /// WNAM when authored, else the two-second default. "Abrupt Transition"
    /// forces a hard cut, which is the same code path with a zero-length ramp.
    private static func crossfade(for type: MusicType) -> Float {
        if type.flags.contains(.abruptTransition) {
            return 0
        }
        return max(type.fadeDuration ?? defaultCrossfadeSeconds, 0)
    }

    /// Flattens palette tracks (a MUST whose CNAM is the palette tag carries
    /// SNAM children instead of an ANAM). Bounded by `maximumPaletteDepth` and
    /// by a visited set, so a palette that references itself terminates.
    private static func expandPalettes(
        _ tracks: [MusicTrack],
        musicStore: MusicRecordStore
    ) -> [MusicTrack] {
        var visited: Set<UInt32> = []
        var out: [MusicTrack] = []
        for track in tracks {
            appendExpanded(
                track, musicStore: musicStore, depth: 0, visited: &visited, into: &out
            )
        }
        return out
    }

    private static func appendExpanded(
        _ track: MusicTrack,
        musicStore: MusicRecordStore,
        depth: Int,
        visited: inout Set<UInt32>,
        into out: inout [MusicTrack]
    ) {
        guard track.trackType == .palette, depth < maximumPaletteDepth else {
            out.append(track)
            return
        }
        guard visited.insert(track.formID.rawValue).inserted else { return }
        for childID in track.tracks {
            guard let child = musicStore.musicTrack(childID) else { continue }
            appendExpanded(
                child, musicStore: musicStore, depth: depth + 1, visited: &visited, into: &out
            )
        }
    }

    /// Drops what cannot be streamed: silent tracks (no ANAM by definition) and
    /// tracks whose filename fails the `music\` path rules. Order is preserved.
    private static func playableTracks(
        _ tracks: [MusicTrack],
        musicStore: MusicRecordStore
    ) -> [PlayableMusicTrack] {
        tracks.compactMap { track in
            guard let path = musicStore.audioPaths(for: track).first else { return nil }
            return PlayableMusicTrack(
                formID: track.formID, editorID: track.editorID, path: path
            )
        }
    }

    /// Fisher-Yates over a seeded generator. Hand-rolled rather than
    /// `shuffled(using:)` so the ordering is pinned by this repository, not by
    /// whatever the standard library's algorithm happens to be.
    static func deterministicOrder(
        _ tracks: [PlayableMusicTrack],
        seed: UInt64
    ) -> [PlayableMusicTrack] {
        guard tracks.count > 1 else { return tracks }
        var generator = SplitMix64(seed: seed)
        var out = tracks
        for index in stride(from: out.count - 1, to: 0, by: -1) {
            let pick = Int(generator.next(upperBound: UInt64(index + 1)))
            out.swapAt(index, pick)
        }
        return out
    }
}

nonisolated extension SplitMix64 {
    /// Unbiased draw in `0 ..< upperBound` by rejection sampling. Shared
    /// generator (weather rolls use the same one) so a "random" music pick has
    /// the same platform-stable, reproducible stream the rest of the engine
    /// relies on.
    mutating func next(upperBound: UInt64) -> UInt64 {
        guard upperBound > 1 else { return 0 }
        let limit = UInt64.max - (UInt64.max % upperBound)
        var value = next()
        while value >= limit {
            value = next()
        }
        return value % upperBound
    }
}
