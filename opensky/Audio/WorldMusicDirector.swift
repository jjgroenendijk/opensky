// Music director (M9.2.3, issue #156): the runtime half of music selection.
// Subscribes to the streamer's music-context callback, resolves it through
// `MusicSelection`, and owns the non-positional source(s) that play the result.
//
// Separate from WorldAudioSoundDirector on purpose: that class already owns the
// SFX + ambience state machine, and music has its own lifetime rules (the
// director, not the engine, retires a music source — non-positional sources are
// exempt from both the FIFO budget and the cell purge).
//
// Main-actor only, like the rest of the audio stack. Defensive throughout: an
// absent engine, store, or file degrades to silence and a readable reason, never
// a crash. Design + policy: docs/engine/music.md.

import Foundation
import OSLog

@MainActor
final class WorldMusicDirector {
    static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "WorldMusicDirector"
    )

    private let engine: WorldAudioEngine
    private let musicStore: MusicRecordStore?
    private let weatherStore: WeatherStore?
    /// Resolves a canonical music path to its file bytes. Production wraps
    /// `VirtualFileSystem.contents(forPath:)`; tests inject a stub.
    private let fileLoader: (String) throws -> Data

    /// Music playback. Toggling takes effect immediately: off fades the current
    /// track out, on restarts the selection the last context resolved.
    var musicEnabled = true {
        didSet {
            guard musicEnabled != oldValue else { return }
            applyMusicState()
        }
    }

    /// Selection the last context (or force control) resolved to, whether or
    /// not it is playing. Diffed against a fresh context to skip no-op
    /// restarts, and re-used as what to start when music is switched back on.
    private var desiredSelection = MusicSelection.silent(state: .exploration)
    /// Index into `desiredSelection.tracks` of the track that should sound.
    private var trackIndex = 0
    /// The one source this director considers current. Nil while silent.
    private var currentSourceID: Int?
    /// Sources fading out on their way to retirement. Tracked separately so a
    /// departing track's disappearance is never mistaken for the current track
    /// finishing.
    private var retiringSourceIDs: [Int] = []
    /// Seconds the current track has been sounding, advanced from the frame
    /// delta so it freezes with the world sim.
    private(set) var currentTrackElapsedSeconds: Float = 0

    /// Most recent failure reason; nil when the last start succeeded.
    private(set) var lastMusicError: String?

    init(
        engine: WorldAudioEngine,
        musicStore: MusicRecordStore?,
        weatherStore: WeatherStore?,
        fileSystem: VirtualFileSystem?
    ) {
        self.engine = engine
        self.musicStore = musicStore
        self.weatherStore = weatherStore
        fileLoader = { path in
            guard let fileSystem else {
                throw NSError(domain: "WorldMusicDirector", code: 1)
            }
            return try fileSystem.contents(forPath: path)
        }
    }

    /// Test seam: same shape as the production init but takes a file loader
    /// closure directly so tests need no VirtualFileSystem.
    init(
        engine: WorldAudioEngine,
        musicStore: MusicRecordStore?,
        weatherStore: WeatherStore?,
        fileLoader: @escaping (String) throws -> Data
    ) {
        self.engine = engine
        self.musicStore = musicStore
        self.weatherStore = weatherStore
        self.fileLoader = fileLoader
    }

    // MARK: - Streamer event hook

    /// `CellStreamer.onMusicContextChanged` subscriber. Resolves the playlist
    /// and, when it differs from the current one, crossfades to it. A context
    /// that resolves to the same selection is a no-op (the track keeps playing
    /// across a cell boundary); one that arrives while music is off is
    /// remembered but not started.
    func handleMusicContext(_ context: MusicContext) {
        let selection = MusicSelection.resolve(
            context: context, musicStore: musicStore, weatherStore: weatherStore
        )
        adopt(selection)
    }

    /// Per-frame drive. `deltaTime` is the renderer's paused-aware delta, so a
    /// paused world neither advances the elapsed readout nor rolls the playlist
    /// over. Playlist advance is detected by the current source having left the
    /// engine: `WorldAudioEngine.tick` retires a stream that reached its end.
    func tick(deltaTime: Float) {
        pruneRetiringSources()
        guard let sourceID = currentSourceID else { return }
        guard engine.sources.contains(where: { $0.id == sourceID }) else {
            currentSourceID = nil
            advancePlaylist()
            return
        }
        if deltaTime > 0 {
            currentTrackElapsedSeconds += deltaTime
        }
    }

    // MARK: - Panel entry points (stage 4 verification surface)

    /// MUSC editor ids the panel can offer, sorted. Empty without music data.
    var selectableMusicTypeNames: [String] {
        guard let musicStore else { return [] }
        return musicStore.musicTypes.values
            .compactMap(\.editorID)
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// Forces a crossfade to a named MUSC, bypassing the precedence chain. The
    /// forced selection becomes the remembered one, so toggling music off and
    /// on restarts it. Returns nil on success or a short failure reason.
    @discardableResult
    func forcePlayMusicType(named name: String) -> String? {
        guard let musicStore else {
            lastMusicError = "no music data"
            return lastMusicError
        }
        guard
            let match = musicStore.musicTypes.values.first(where: { $0.editorID == name })
        else {
            lastMusicError = "unknown music type \(name)"
            return lastMusicError
        }
        return forcePlayMusicType(formID: match.formID)
    }

    /// Forces a crossfade to a MUSC by FormID. Mirrors
    /// `WorldAudioSoundDirector.forcePlaySound(formID:position:)`.
    @discardableResult
    func forcePlayMusicType(formID: FormID) -> String? {
        guard let musicStore else {
            lastMusicError = "no music data"
            return lastMusicError
        }
        let selection = MusicSelection.resolve(musicType: formID, musicStore: musicStore)
        guard !selection.isSilent else {
            lastMusicError = "no playable track for \(formID.description)"
            return lastMusicError
        }
        adopt(selection, force: true)
        return lastMusicError
    }

    /// Force-stops music by adopting the empty context. The next cell change
    /// resolves a fresh selection and starts it again.
    func stopMusic() {
        handleMusicContext(.empty)
    }

    /// What the panel readout shows. Derived from live engine sources: the id
    /// is dropped first if the engine already retired it, so the readout can
    /// never claim music that stopped. "none" when nothing of ours is playing.
    var currentMusicDescription: String {
        guard let name = currentTrackName else { return "none" }
        return "\(desiredSelection.displayName) — \(name)"
    }

    /// VFS path of the track currently sounding, or nil when silent.
    var currentTrackName: String? {
        guard let currentSourceID else { return nil }
        return engine.sources.first { $0.id == currentSourceID }?.name
    }

    /// Name of the derived state (`exploration`, `town`, `interior`).
    var currentStateName: String {
        desiredSelection.state.displayName
    }

    /// Crossfade the current selection uses, for the readout.
    var currentCrossfadeSeconds: Float {
        desiredSelection.crossfadeSeconds
    }

    /// Position in the current playlist, as `index + 1` of `count`. Zero-based
    /// index and a zero count when silent.
    var playlistPosition: (index: Int, count: Int) {
        (desiredSelection.isSilent ? 0 : trackIndex, desiredSelection.tracks.count)
    }

    // MARK: - State machine

    private func adopt(_ selection: MusicSelection, force: Bool = false) {
        guard force || selection != desiredSelection else { return }
        desiredSelection = selection
        trackIndex = 0
        applyMusicState()
    }

    /// Single path from wanted state to playing state, shared by the context
    /// change, the force control and the enable toggle so they cannot drift.
    private func applyMusicState() {
        guard musicEnabled, engine.isRunning else {
            // Switching music off (or losing the engine) stops now rather than
            // fading: the user asked for silence, not for a slow one.
            retireMusicSources(overSeconds: 0)
            return
        }
        startTrack(at: trackIndex)
    }

    /// Starts the track at `index`, crossfading out whatever is playing. A
    /// track whose file will not load is skipped and the next one tried, so one
    /// missing asset cannot silence a whole playlist; the walk is bounded by
    /// the playlist length.
    private func startTrack(at index: Int) {
        let tracks = desiredSelection.tracks
        guard !tracks.isEmpty else {
            retireMusicSources(overSeconds: desiredSelection.crossfadeSeconds)
            return
        }
        let duration = desiredSelection.crossfadeSeconds
        for offset in 0 ..< tracks.count {
            let candidate = (index + offset) % tracks.count
            guard let sourceID = startSource(for: tracks[candidate]) else { continue }
            crossfade(incoming: sourceID, overSeconds: duration)
            trackIndex = candidate
            currentTrackElapsedSeconds = 0
            lastMusicError = nil
            return
        }
        retireMusicSources(overSeconds: duration)
    }

    /// Starts one playable track as a non-positional music source. Returns nil
    /// (with `lastMusicError` set) when the file or the engine refuses.
    private func startSource(for track: PlayableMusicTrack) -> Int? {
        do {
            let data = try fileLoader(track.path)
            return try engine.playNonPositional(
                fileData: data,
                request: .nonPositional(
                    name: track.path,
                    category: .music,
                    gain: 1,
                    // `.repeatCurrent` has the engine rewind at end of file;
                    // the other policies want the source to end so the director
                    // sees the track finish.
                    loops: desiredSelection.advance == .repeatCurrent
                )
            )
        } catch {
            let reason = "\(track.path): \(String(describing: error))"
            lastMusicError = reason
            Self.logger.warning(
                "[WARNING] music start failed: \(reason, privacy: .public)"
            )
            return nil
        }
    }

    /// The crossfade recipe: the incoming source starts silent, the outgoing
    /// one ramps to silence and retires itself, and the incoming one ramps up
    /// over the same window. A zero duration applies both ends immediately,
    /// which is the "Abrupt Transition" flag's hard cut.
    private func crossfade(incoming: Int, overSeconds duration: Float) {
        engine.fadeSource(id: incoming, to: 0, overSeconds: 0)
        retireMusicSources(overSeconds: duration)
        engine.fadeSource(id: incoming, to: 1, overSeconds: duration)
        currentSourceID = incoming
    }

    /// Fades every source this director owns out and hands it to the engine to
    /// retire at the end of the ramp.
    private func retireMusicSources(overSeconds duration: Float) {
        if let currentSourceID {
            engine.fadeOutAndStopSource(id: currentSourceID, overSeconds: duration)
            retiringSourceIDs.append(currentSourceID)
        }
        currentSourceID = nil
        currentTrackElapsedSeconds = 0
        pruneRetiringSources()
    }

    private func advancePlaylist() {
        switch desiredSelection.advance {
        case .cycle:
            guard !desiredSelection.tracks.isEmpty else { return }
            startTrack(at: (trackIndex + 1) % desiredSelection.tracks.count)
        case .stopAfterOne, .repeatCurrent:
            // One-selection playlists end in silence; a repeating one loops in
            // the engine, so reaching here means it was retired for another
            // reason. Either way there is nothing to start.
            currentTrackElapsedSeconds = 0
        }
    }

    /// Forgets ids the engine has already dropped, so the tracked set only ever
    /// names sources that still exist.
    private func pruneRetiringSources() {
        let live = Set(engine.sources.map(\.id))
        retiringSourceIDs.removeAll { !live.contains($0) }
    }
}
