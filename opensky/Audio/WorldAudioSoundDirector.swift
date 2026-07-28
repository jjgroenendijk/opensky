// World SFX + ambience director (M9.2.2, issue #155). Subscribes to the
// streamer's interaction + ambience-context callbacks and drives the audio
// engine accordingly:
//
//   - One-shot SFX (door open, activator activate) on use-key events, routed
//     through the descriptor's SNDR.GNAM -> SNCT parent chain.
//   - Continuous ambience loop set when the center cell changes, using the
//     same authored category resolution, fired from the listener position
//     (a stopgap until
//     a non-positional bed path exists; see issue #236). Bed sources are
//     started as loops, so they rewind in the streamer rather than ending
//     after one pass; the panel toggle retires and restarts them live.
//
// Main-actor only (the engine + streamer are main-actor); decode work runs
// inside WorldAudioEngine's decode queue. Defensive: an absent engine, store,
// or file-system entry degrades silently — no audio, no crash. The director
// is the single consumer of the CellStreamer.onInteraction seam the M8 work
// reserved for "the later Papyrus OnActivate subscriber"; that Papyrus
// subscriber will subscribe alongside, not replace this one.

import Foundation
import OSLog
import simd

private struct ResolvedAudioFile {
    let data: Data
    let name: String
    let category: AudioCategory
}

@MainActor
final class WorldAudioSoundDirector {
    static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "WorldAudioDirector"
    )

    private let engine: WorldAudioEngine
    private let soundStore: SoundRecordStore?
    private let weatherStore: WeatherStore?
    private let aspcStore: AcousticSpaceStore?
    /// Resolves a canonical sound-path string to its file bytes. Production
    /// wraps `VirtualFileSystem.contents(forPath:)`; tests inject a stub.
    private let fileLoader: (String) throws -> Data

    /// SFX on use-key activation. Off by default until the user enables audio;
    /// the panel control writes back here.
    var sfxEnabled = true
    /// Continuous ambience bed. Same default policy as `sfxEnabled`. Toggling
    /// it takes effect immediately: switching off retires the playing bed,
    /// switching back on restarts the bed the last context resolved.
    var ambienceEnabled = true {
        didSet {
            guard ambienceEnabled != oldValue else { return }
            applyAmbienceState()
        }
    }

    /// Active ambience source ids owned by this director. Tracked so a context
    /// change can retire exactly the previous bed without touching unrelated
    /// one-shot SFX the engine is also playing.
    private var ambienceSourceIDs: [Int] = []
    /// Bed the last context resolved to, whether or not it is playing. Diffed
    /// against a fresh context to skip no-op restarts, and re-used as the bed
    /// to start when ambience is switched back on.
    private var desiredBed = AmbienceBed.empty
    /// Authored motion loops by placed reference. A close or cancelled
    /// animation boundary retires exactly its loop without touching ambience
    /// or unrelated effects.
    private var interactionLoopSourceIDs: [FormID: Int] = [:]

    /// Most recent SFX outcome, surfaced through the World > Audio readout.
    private(set) var lastSFXDescription: String?
    private(set) var lastSFXError: String?

    init(
        engine: WorldAudioEngine,
        soundStore: SoundRecordStore?,
        weatherStore: WeatherStore?,
        aspcStore: AcousticSpaceStore?,
        fileSystem: VirtualFileSystem?
    ) {
        self.engine = engine
        self.soundStore = soundStore
        self.weatherStore = weatherStore
        self.aspcStore = aspcStore
        fileLoader = { path in
            guard let fileSystem else {
                throw NSError(domain: "WorldAudioSoundDirector", code: 1)
            }
            return try fileSystem.contents(forPath: path)
        }
    }

    /// Test seam: same shape as the production init but takes a file loader
    /// closure directly so tests do not need a real VirtualFileSystem.
    init(
        engine: WorldAudioEngine,
        soundStore: SoundRecordStore?,
        weatherStore: WeatherStore?,
        aspcStore: AcousticSpaceStore?,
        fileLoader: @escaping (String) throws -> Data
    ) {
        self.engine = engine
        self.soundStore = soundStore
        self.weatherStore = weatherStore
        self.aspcStore = aspcStore
        self.fileLoader = fileLoader
    }

    // MARK: - Streamer event hooks

    /// CellStreamer.onInteraction subscriber. Plays the activator's activation
    /// sound (DOOR.SNAM, ACTI.VNAM, CONT.SNAM) at the placed position.
    func handleInteraction(_ event: InteractionEvent) {
        guard sfxEnabled, engine.isRunning else { return }
        guard
            let sounds = event.target.interaction.sounds,
            let activationID = sounds.activation
        else { return }
        playResolved(
            id: activationID,
            at: event.target.interaction.position,
            kind: "SFX"
        )
    }

    /// Door-animation lifecycle subscriber. Movement starts the authored loop;
    /// close and cancellation both retire it, while only close plays the
    /// authored one-shot. The same event also supports a future container
    /// animation because DOOR.ANAM and CONT.QNAM share `sounds.close`.
    func handleInteractionAnimation(_ event: InteractionAnimationEvent) {
        let interaction = event.interaction
        switch event.phase {
        case .motionStarted:
            retireInteractionLoop(reference: interaction.reference)
            guard
                sfxEnabled,
                engine.isRunning,
                let loopID = interaction.sounds?.loop
            else { return }
            interactionLoopSourceIDs[interaction.reference] = playResolved(
                id: loopID,
                at: interaction.position,
                kind: "interaction loop",
                loops: true
            )
        case .closed:
            retireInteractionLoop(reference: interaction.reference)
            guard
                sfxEnabled,
                engine.isRunning,
                let closeID = interaction.sounds?.close
            else { return }
            playResolved(
                id: closeID,
                at: interaction.position,
                kind: "interaction close"
            )
        case .cancelled:
            retireInteractionLoop(reference: interaction.reference)
        }
    }

    /// CellStreamer.onAmbienceContextChanged subscriber. Resolves the new bed
    /// and, when it differs from the last resolved one, retires the previous
    /// sources and starts the new ones. A bed that did not change is a no-op;
    /// a bed resolved while ambience is off is remembered but not started.
    func handleAmbienceContext(_ context: AmbienceContext) {
        let bed = AmbienceBed.resolve(
            context: context,
            weatherStore: weatherStore,
            aspcStore: aspcStore
        )
        guard bed != desiredBed else { return }
        desiredBed = bed
        applyAmbienceState()
    }

    /// Single path from wanted state to playing state, shared by the context
    /// change and the panel toggle so the two cannot drift apart.
    private func applyAmbienceState() {
        retireAmbience()
        guard ambienceEnabled, engine.isRunning else { return }
        startAmbience(bed: desiredBed)
    }

    // MARK: - Panel entry points (Phase 3 verification surface)

    /// Forces a one-shot SFX for any resolved SNDR FormID. Used by the World >
    /// Audio panel to verify SFX without relying on a walk-mode interaction.
    func forcePlaySound(formID: FormID, position: SIMD3<Float>) {
        guard engine.isRunning else {
            lastSFXError = "engine not running"
            return
        }
        playResolved(id: formID, at: position, kind: "SFX")
    }

    /// Ambience bed the panel readout shows. Reports "none" unless at least one
    /// of this director's ambience sources is still alive in the engine, so the
    /// readout cannot claim a bed the engine already retired (FIFO eviction,
    /// cell purge, or a stream that ended).
    var currentAmbienceDescription: String {
        pruneRetiredAmbienceSources()
        guard !ambienceSourceIDs.isEmpty else { return "none" }
        return desiredBed.entries
            .map(\.sound.description)
            .joined(separator: ", ")
    }

    // MARK: - Internals

    @discardableResult
    private func playResolved(
        id: FormID,
        at position: SIMD3<Float>,
        kind: String,
        loops: Bool = false
    ) -> Int? {
        guard let resolved = resolveSound(id: id) else {
            lastSFXError = "unresolved \(id.description)"
            Self.logger.debug(
                "[INFO] \(kind, privacy: .public) unresolved: \(id.description, privacy: .public)"
            )
            return nil
        }
        do {
            let sourceID = try engine.playPositional(
                fileData: resolved.data,
                request: AudioPlayRequest(
                    name: resolved.name,
                    category: resolved.category,
                    worldPosition: position,
                    loops: loops
                )
            )
            lastSFXDescription = resolved.name
            lastSFXError = nil
            return sourceID
        } catch {
            let reason = String(describing: error)
            lastSFXError = reason
            Self.logger.warning(
                "[WARNING] \(kind, privacy: .public) play failed: \(reason, privacy: .public)"
            )
            return nil
        }
    }

    private func retireInteractionLoop(reference: FormID) {
        guard let sourceID = interactionLoopSourceIDs.removeValue(forKey: reference) else {
            return
        }
        engine.stopSource(id: sourceID)
    }

    private func startAmbience(bed: AmbienceBed) {
        // Stopgap: ambience plays positional at the listener. A future
        // non-positional bed path (issue #236) replaces this.
        let position = engine.listenerWorldPosition
        for entry in bed.entries {
            guard let resolved = resolveSound(id: entry.sound) else { continue }
            do {
                let sourceID = try engine.playPositional(
                    fileData: resolved.data,
                    request: AudioPlayRequest(
                        name: resolved.name,
                        category: resolved.category,
                        worldPosition: position,
                        gain: ambienceGainPerEntry(in: bed),
                        // A bed is continuous: the streamer rewinds at end of
                        // file instead of letting the engine retire it.
                        loops: true
                    )
                )
                ambienceSourceIDs.append(sourceID)
            } catch {
                let reason = String(describing: error)
                Self.logger.warning(
                    "[WARNING] ambience start failed: \(reason, privacy: .public)"
                )
            }
        }
    }

    /// Splits unity across the bed entries so N concurrent loops do not sum to
    /// N x master. Equal-weight today; the RDSA.Chance field (issue pending
    /// probe) will refine this.
    private func ambienceGainPerEntry(in bed: AmbienceBed) -> Float {
        bed.entries.isEmpty ? 1 : 1 / Float(bed.entries.count)
    }

    private func retireAmbience() {
        for id in ambienceSourceIDs {
            engine.stopSource(id: id)
        }
        ambienceSourceIDs.removeAll()
    }

    /// Forgets ids the engine already stopped on its own, so the tracked set
    /// only ever names sources that are actually playing.
    private func pruneRetiredAmbienceSources() {
        let live = Set(engine.sources.map(\.id))
        ambienceSourceIDs.removeAll { !live.contains($0) }
    }

    private func resolveSound(id: FormID) -> ResolvedAudioFile? {
        guard let soundStore else { return nil }
        let resolved: ResolvedSound
        do {
            resolved = try soundStore.resolveAny(id)
        } catch {
            return nil
        }
        guard let path = resolved.filePaths.first else { return nil }
        guard let data = try? fileLoader(path) else { return nil }
        return ResolvedAudioFile(
            data: data,
            name: path,
            category: resolved.audioCategory ?? .effects
        )
    }
}
